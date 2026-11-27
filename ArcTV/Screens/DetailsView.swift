import ArcKit
import SwiftUI

/// What the player is asked to play, and from where in the file.
struct PlayRequest: Identifiable, Hashable {
    let item: Item
    let startMs: Int64
    /// Played in a Watch Together room: the room decides where and whether it plays.
    var together = false
    /// The player moving on by itself (Up Next, the queue): no pre-rolls.
    var playingOn = false
    /// The play queue's entry this is (Home's Queue row, Shuffle, the queue moving on).
    var queueEntry: String?
    var id: String { item.id + "@\(startMs)" + (together ? "|together" : "") + (playingOn ? "|on" : "") }

    /// A film started from the beginning plays the pre-roll videos first, as on the web: not when
    /// resuming, in Watch Together, or when the player moves on.
    var wantsPreroll: Bool { item.kind == "movie" && startMs == 0 && !together && !playingOn }
}

/// A title's page: its background, logo or title, details, Play and its actions; a show's seasons
/// and episodes; then its cast, collections and More Like This, as Plex's page.
struct DetailsView: View {
    @Environment(AppModel.self) private var app
    @Environment(Browse.self) private var browse
    @Environment(\.openRoute) private var openRoute
    let itemId: String
    let initial: Item
    /// Opened from an episode's card: the show's page lands on this episode, in its season, with
    /// the episodes showing (as Plex, and arc-android's linked episode).
    var episodeId: String? = nil

    @State private var item: Item?
    @State private var similar: [Item] = []
    @FocusState private var focused: String?
    @State private var seasons: [Season] = []
    @State private var season = 0
    /// The season just marked watched or unwatched, kept showing when the page reads again.
    @State private var keepSeason: Int?
    /// Show Missing Episodes: the episodes the show's provider knows about that have no file,
    /// for as long as the page is open (as the web's switch; not saved).
    @State private var showMissing = false
    /// The artwork's four colours from the server, blended behind the whole page: what's left
    /// when the artwork slides away for a show's episodes.
    @State private var wash: [Color]?
    /// The artwork has slid away for a show's episodes. It stays away below them (Related, Cast)
    /// and comes back only with the hero.
    @State private var receded = false
    /// The page opens on its artwork alone; the hero's words fade in a moment later, as the
    /// reference does. (A mask, so Play can take the focus straight away.)
    @State private var entered = false
    @State private var problem: String?
    @State private var extra: Extra?
    /// The title's theme tune, played once per visit (not again on coming back from the player).
    @State private var theme = ThemeMusic()
    @State private var themePlayed = false
    /// The episode the page is about to land on (`episodeId`), once its season is showing; and
    /// whether it has, so reading the page again later doesn't move the focus.
    @State private var landing: String?
    @State private var landed = false

    private var shown: Item { item ?? initial }
    private var backdropPath: String? { shown.images?.backdrop ?? shown.images?.seriesBackdrop }
    /// Whose backdrop is showing: the title's own, or for an episode without one, its show's.
    private var paletteSource: String? {
        shown.images?.backdrop != nil ? shown.id : (shown.images?.seriesBackdrop != nil ? shown.parentId : shown.id)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Behind everything, the artwork's own colours blended corner to corner.
            PageWash(colors: wash)
            // The artwork fades into that blend at the bottom and the left (masks rather than
            // a colour on top, so the blend shows through).
            ArtworkImage(path: backdropPath)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Gentle, as the reference: the picture stays bright to near the bottom and only
                // softens behind the words on the left.
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.6),
                                             .init(color: .black.opacity(0.45), location: 1)], startPoint: .top, endPoint: .bottom))
                .mask(LinearGradient(stops: [.init(color: .black.opacity(0.5), location: 0), .init(color: .black, location: 0.55)],
                                     startPoint: .leading, endPoint: .trailing))
                .ignoresSafeArea()
                // Below the hero (a show's episodes, the rows under it) the artwork dims behind
                // the page, as Android's title page (owner, 27 November).
                .opacity(receded ? 0.35 : 1)
                .animation(Self.recede, value: receded)
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 28) {
                        hero
                            // The words fade in a moment after the artwork: a mask rather than
                            // opacity, so Play can take the focus at once (tvOS won't focus a
                            // fully transparent view). Larger than the hero, so a focused
                            // button's lift and shadow aren't cut off.
                            .mask(Rectangle().opacity(entered ? 1 : 0).padding(-80))
                            .id(Self.heroAnchor)
                        if !seasons.isEmpty {
                            episodes
                        } else {
                            // A film's hero has nothing peeking under it, as the reference: the
                            // next row starts just below the screen, and Down scrolls to it.
                            Color.clear.frame(height: 1).id(Self.restAnchor)
                            // Enough to keep the cast just below the screen at first, and
                            // close under the buttons once Down brings it up (owner, 27 November).
                            Color.clear.frame(height: 50).accessibilityHidden(true)
                        }
                        // The cast first, above every other row (owner, 7 November).
                        if !actors.isEmpty { cast }
                        if !shown.extras.isEmpty { extras }
                        if !similar.isEmpty { related }
                        if !shown.collections.isEmpty { collections }
                        infoCards
                    }
                    .padding(.horizontal, Self.pageInset)
                    .padding(.bottom, 60)
                }
                .defaultFocus($focused, Self.playKey)
                // Opened from an episode's card: along to it in its row, then the focus onto it,
                // which brings the episodes up as Down from Play does.
                .onChange(of: landing) { _, id in
                    guard let id else { return }
                    proxy.scrollTo(id, anchor: .leading)
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(120))
                        focused = "ep|" + id
                        try? await Task.sleep(for: .milliseconds(400))
                        landing = nil
                    }
                }
                .onChange(of: focused) { old, new in
                    if let new, new.hasPrefix("season|"), let index = Int(new.dropFirst(7)), index != season {
                        if old?.hasPrefix("season|") == true {
                            // Moving along the season tabs shows that season's episodes; no Select.
                            withAnimation(.easeInOut(duration: 0.2)) { season = index }
                        } else {
                            // Coming into the tabs (from the episodes or the hero) lands on the
                            // season showing, whichever tab is nearest. (A step later: tvOS
                            // ignores a focus change made while it's moving the focus.)
                            Task { @MainActor in focused = "season|\(season)" }
                        }
                    }
                    // Into the episodes from the hero: on to the one to watch next. (After tvOS's
                    // own move has settled: it ignores a change made while it's moving the focus.)
                    if Self.isHero(old), let new, new.hasPrefix("ep|"), new != landing.map({ "ep|" + $0 }),
                       let next = seasonNextUp, new != "ep|" + next.id {
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(80))
                            focused = "ep|" + next.id
                        }
                    }
                    // A film: Down from the hero brings the first row up under the hero's buttons,
                    // which stay at the top, as the reference does; Up goes back to the whole hero.
                    // (The first row's cards carry focus keys, so the hero is Play's key or nil.)
                    if seasons.isEmpty {
                        if Self.isFirstRow(new), Self.isHero(old) {
                            withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(Self.restAnchor, anchor: Self.restPoint) }
                        } else if Self.isFirstRow(old), Self.isHero(new) {
                            withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(Self.heroAnchor, anchor: .top) }
                        }
                    }
                    let wasBrowsing = Self.isBrowser(old), nowBrowsing = Self.isBrowser(new)
                    if nowBrowsing && !wasBrowsing {
                        withAnimation(Self.recede) { receded = true }
                    }
                    // The season tabs and episodes land at the foot of the screen, with the page
                    // above them in view, as Android's: on the way in, and from the tabs down to
                    // the episodes. A moment later, so tvOS's own scroll for the focus (which
                    // shows only as much as the focused tab or card) doesn't override it.
                    if nowBrowsing, !(old?.hasPrefix("ep|") == true && new?.hasPrefix("ep|") == true) {
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(60))
                            withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(Self.browserAnchor, anchor: .bottom) }
                        }
                    } else if !nowBrowsing && old?.hasPrefix("season|") == true && Self.isHero(new) {
                        // Up from the season tabs is the hero's buttons: back to the top.
                        withAnimation(Self.recede) {
                            receded = false
                            proxy.scrollTo(Self.heroAnchor, anchor: .top)
                        }
                    }
                }
            }
        }
        .onAppear {
            guard !entered else { return }
            withAnimation(.easeOut(duration: 0.4).delay(0.35)) { entered = true }
        }
        .task(id: "\(browse.changes)|\(showMissing)") { await load() }
        // Live updates: the page reloads in place when Arc says the title changed (not under the
        // player: it reads again after playing anyway).
        .onChange(of: app.liveTitle) {
            guard browse.playing == nil else { return }
            // Staying on the season being looked at.
            if seasons.indices.contains(season) { keepSeason = seasons[season].seasonNumber }
            Task { await load() }
        }
        .task(id: paletteSource) {
            // The server keeps each backdrop's colours; an older server without them, or a title
            // without artwork, keeps Arc's grey blend.
            guard let id = paletteSource, let api = app.api,
                  let colors = try? await api.palette(id).background else { return }
            wash = colors.map(Color.init)
        }
        .fullScreenCover(item: $extra) { ExtraPlayerScreen(extra: $0) }
        // The theme tune, once the title is read; it fades out when anything opens over the page.
        .task(id: item?.id) { await startTheme() }
        .onDisappear { theme.stop() }
        .onChange(of: browse.playing) { _, now in if now != nil { theme.stop() } }
        .onChange(of: extra?.id) { _, now in if now != nil { theme.stop() } }
    }

    /// Plays the theme tune of a film or show (not an episode), as the web does, when the
    /// profile's Theme Music is on.
    private func startTheme() async {
        guard !themePlayed, let item, !item.isEpisode, let path = item.themeUrl,
              browse.playing == nil, let api = app.api, let url = api.absolute(path) else { return }
        themePlayed = true
        // On unless turned off; if the preferences can't be read, play it as the web would.
        let on = (try? await api.prefs())?.themeMusic ?? true
        guard on, !Task.isCancelled, browse.playing == nil else { return }
        theme.play(url, headers: api.authorization)
    }

    /// Trailers and other extras, as Plex's page has them; each plays in a simple player.
    private var extras: some View {
        section(L("details.extras")) {
            ForEach(shown.extras) { e in
                VStack(alignment: .leading, spacing: 10) {
                    Button { extra = e } label: {
                        ZStack {
                            ArtworkImage(path: shown.images?.backdrop ?? shown.images?.seriesBackdrop).frame(width: 384, height: 216)
                            Image(systemName: "play.circle.fill").font(.system(size: 54)).foregroundStyle(.white.opacity(0.9))
                        }
                        .frame(width: 384, height: 216)
                        .clipShape(RoundedRectangle(cornerRadius: cardCorner, style: .continuous))
                    }
                    .buttonStyle(.card)
                    .focused($focused, equals: "extra|" + e.id)
                    Group {
                        Text(e.title).font(.caption.weight(.semibold)).lineLimit(1).frame(width: 384, alignment: .leading)
                        Text(extraKind(e)).font(.caption2).foregroundStyle(ArcColor.muted)
                    }
                    .belowLiftedCard(focused == "extra|" + e.id)
                }
            }
        }
    }

    private func extraKind(_ e: Extra) -> String {
        var parts = [L("extra." + (["trailer", "featurette", "behindthescenes", "deleted", "interview", "scene", "short"].contains(e.kind) ? e.kind : "other"))]
        if e.durationMs > 0 {
            let s = Int(e.durationMs / 1000)
            parts.append(String(format: "%d:%02d", s / 60, s % 60))
        }
        return parts.joined(separator: " · ")
    }

    /// The title hero: logo, the rating boxed with the genres, the overview, the year, length
    /// and the file's quality badges, the buttons; who's in it and who directed it on the right.
    private var hero: some View {
        HStack(alignment: .bottom, spacing: 60) {
            VStack(alignment: .leading, spacing: 22) {
                TitleLogo(path: shown.images?.logo, title: shown.title)
                HStack(spacing: 12) {
                    if let rating = shown.contentRating, !rating.isEmpty { OutlinedBadge(text: rating) }
                    if !shown.genres.isEmpty { Text(shown.genres.prefix(3).joined(separator: " · ")) }
                }
                .font(.callout.weight(.medium))
                if let overview = shown.overview(hidingSpoilers: app.hideSpoilers) {
                    Text(overview).font(.callout).foregroundStyle(.white.opacity(0.85)).lineLimit(4).frame(maxWidth: 900, alignment: .leading)
                }
                HStack(spacing: 12) {
                    if !facts.isEmpty { Text(facts) }
                    ForEach(Array(Quality.capsules(Quality.file(of: shown)).enumerated()), id: \.offset) { QualityCapsule(capsule: $0.element) }
                }
                .font(.callout.weight(.medium)).foregroundStyle(.white.opacity(0.85))
                if let problem { Text(problem).foregroundStyle(ArcColor.error) }
                buttons
                    // Out of reach while an episode has the focus, so Up from the episodes always
                    // lands on the season tabs; from the tabs, Up reaches them again.
                    .disabled(focused?.hasPrefix("ep|") == true)
            }
            Spacer(minLength: 0)
            people
        }
        // Low on the screen, as Android's page: a film's buttons a margin above the bottom, a
        // show's just above its season tabs, which peek in under them (owner, 27 November).
        .frame(minHeight: seasons.isEmpty && !shown.isSeries ? 940 : 870, alignment: .bottomLeading)
    }

    /// The year (or a show's first year) and the length.
    private var facts: String {
        var parts: [String] = []
        if let yearAndEdition = shown.yearAndEdition { parts.append(yearAndEdition) }
        if let minutes = shown.runtimeMin, minutes > 0 {
            parts.append(minutes >= 60 ? L("details.runtime", minutes / 60, minutes % 60) : L("card.minutes_short", minutes))
        }
        return parts.joined(separator: " · ")
    }

    private var actors: [Credit] { shown.credits.filter { $0.role == "actor" || $0.role.isEmpty } }
    private func crew(_ role: String) -> [String] { shown.credits.filter { $0.role == role }.map(\.name) }

    /// "Starring A, B and C" and "Director D", bottom right.
    private var people: some View {
        let starring = actors.prefix(3).map(\.name)
        let directors = crew("director")
        return VStack(alignment: .trailing, spacing: 8) {
            if !starring.isEmpty { labelled(L("details.starring"), ListFormatter.localizedString(byJoining: starring)) }
            if !directors.isEmpty { labelled(L("details.role_director"), ListFormatter.localizedString(byJoining: directors)) }
        }
        .font(.caption)
        .multilineTextAlignment(.trailing)
        .frame(maxWidth: 520, alignment: .trailing)
        .padding(.bottom, 12)
    }

    private func labelled(_ label: String, _ value: String) -> Text {
        Text(label + " ").foregroundStyle(ArcColor.muted) + Text(value).fontWeight(.semibold)
    }

    @ViewBuilder private var buttons: some View {
        HStack(spacing: 20) {
            // Play is a glass button like the rest: it turns white only with focus.
            if shown.playable {
                let resume = shown.resumeMs
                Button { play(PlayRequest(item: shown, startMs: resume)) } label: {
                    PlayLabel(item: shown, episode: shown.isEpisode)
                }
                .arcGlassButton()
                .focused($focused, equals: Self.playKey)
                if resume > 0 {
                    Button { play(PlayRequest(item: shown, startMs: 0)) } label: {
                        Label(L("details.from_beginning"), systemImage: "arrow.counterclockwise")
                    }
                    .roundIconButton()
                }
            } else if let next = nextEpisode {
                Button { play(PlayRequest(item: next, startMs: next.resumeMs)) } label: {
                    PlayLabel(item: next, episode: true)
                }
                .arcGlassButton()
                .focused($focused, equals: Self.playKey)
                // A show's episodes in a random order, as a new play queue (as the web's Shuffle).
                if browse.queuesUsable && shuffleCandidates(nil).count > 1 {
                    Button { shuffle(nil) } label: {
                        Label(L("details.shuffle"), systemImage: "shuffle")
                    }
                    .roundIconButton()
                }
            }
            // The page's other actions are round glass icons, as the Android app's title page.
            TitleActions(item: shown, onPage: true).roundIconButton()
        }
        .focusSection()
    }

    private func play(_ request: PlayRequest) { browse.play(request) }

    private var cast: some View {
        section(L("details.cast")) {
            ForEach(actors.prefix(30)) { credit in
                PersonButton(name: credit.name, detail: credit.character ?? roleName(credit.role), image: credit.image,
                             focus: $focused, focusKey: "cast|\(credit.personId)") {
                    openRoute(.person(id: credit.personId, name: credit.name))
                }
            }
        }
    }

    private var collections: some View {
        section(L("details.collections")) {
            ForEach(shown.collections) { c in
                Button(c.title) { openRoute(.collection(id: c.id, title: c.title)) }.arcGlassButton()
            }
        }
    }

    private var related: some View {
        section(L("details.more_like_this")) {
            ForEach(similar) { other in
                MediaCardView(card: MediaCard(item: other), style: .poster, focus: $focused, focusKey: other.id) { openRoute(.item(other)) }
            }
        }
    }

    /// About, Details, Crew and Playback as glass cards at the foot of the page, under an "About"
    /// heading: About across the top, the other three side by side beneath it.
    /// (Arc's ratings are paused, so there's no Ratings card.)
    private var infoCards: some View {
        let file = Quality.file(of: shown)
        let details: [(String, String)] = [
            (L("details.released"), shown.releaseDate.flatMap(releaseDate) ?? shown.year.map(String.init) ?? ""),
            (L("details.runtime_label"), shown.isSeries ? "" : shown.runtimeMin.map { runtimeText($0) } ?? ""),
            (L("details.content_rating"), shown.contentRating ?? ""),
            (L("details.genres"), ListFormatter.localizedString(byJoining: shown.genres)),
            (L("details.original_title"), shown.originalTitle.flatMap { $0 == shown.title ? nil : $0 } ?? ""),
        ].filter { !$0.1.isEmpty }
        let crewLines: [(String, String)] = [
            (L("details.directed_by"), ListFormatter.localizedString(byJoining: crew("director"))),
            (L("details.written_by"), ListFormatter.localizedString(byJoining: crew("writer"))),
            (L("details.studios"), shown.studio ?? ""),
        ].filter { !$0.1.isEmpty }
        let playback = playbackLines(file)
        return VStack(alignment: .leading, spacing: 24) {
            Text(L("details.about")).font(.title3.weight(.semibold))
            if let overview = shown.overview(hidingSpoilers: app.hideSpoilers) {
                InfoCard(title: nil, width: 1100) {
                    Text(shown.title).font(.headline)
                    Text(overview).font(.callout).foregroundStyle(.white.opacity(0.85)).lineLimit(10)
                }
            }
            HStack(alignment: .top, spacing: 30) {
                if !details.isEmpty { InfoCard(title: L("details.details"), width: 530) { lines(details) } }
                if !crewLines.isEmpty { InfoCard(title: L("details.crew"), width: 530) { lines(crewLines) } }
                if !playback.isEmpty { InfoCard(title: L("details.playback"), width: 530) { lines(playback) } }
            }
        }
        .padding(.vertical, 24)
    }

    private func lines(_ pairs: [(String, String)]) -> some View {
        ForEach(pairs, id: \.0) { pair in
            VStack(alignment: .leading, spacing: 2) {
                Text(pair.0).font(.caption2).foregroundStyle(ArcColor.muted)
                Text(pair.1).font(.callout.weight(.semibold)).lineLimit(3)
            }
        }
    }

    /// Where and what it plays: the server, how it's reached, the profile, then the file's
    /// quality in words, its bitrate, size, edition and name.
    private func playbackLines(_ file: MediaFile?) -> [(String, String)] {
        var out: [(String, String)] = []
        if let server = app.serverName, !server.isEmpty { out.append((L("details.server"), server)) }
        if let local = app.onLocalNetwork {
            out.append((L("details.connection"), L(local ? "details.connection_local" : "details.connection_remote")))
        }
        if let profile = app.profile?.name { out.append((L("details.profile"), profile)) }
        guard let file else { return out }
        if let quality = Quality.summary(file) { out.append((L("details.quality"), quality)) }
        // ffprobe's overall bitrate, in bits a second.
        if let bitrate = file.bitrate, bitrate > 0 {
            out.append((L("details.bitrate"), L("details.mbps", Double(bitrate) / 1_000_000)))
        }
        if let size = file.size, size > 0 {
            out.append((L("details.size"), ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))
        }
        if let edition = file.edition, !edition.isEmpty { out.append((L("details.edition"), edition)) }
        if let path = file.path, !path.isEmpty {
            // Only the file's name: Windows and Unix paths both end in it.
            let name = path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? path
            out.append((L("details.file"), name))
        }
        return out
    }

    private func releaseDate(_ iso: String) -> String? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: iso) else { return nil }
        return d.formatted(date: .abbreviated, time: .omitted)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title3.weight(.semibold))
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 40) { content() }.padding(.vertical, 24)
            }
            .scrollClipDisabled()
        }
    }

    private func roleName(_ role: String) -> String? {
        switch role {
        case "director": return L("details.role_director")
        case "writer": return L("details.role_writer")
        case "actor", "": return nil
        default: return role.capitalized
        }
    }

    /// A show's Play: the first episode not yet watched (or part-watched), else the first. It
    /// follows the order: episodes outside it ("Not in This Order", numbered -1) are left out.
    private var nextEpisode: Item? {
        let all = seasons.filter { $0.seasonNumber > 0 }.flatMap(\.episodes) + seasons.filter { $0.seasonNumber == 0 }.flatMap(\.episodes)
        let available = all.filter(\.available)
        return available.first { !$0.watched } ?? available.first
    }

    /// The one clock the move between a show's overview and its episodes runs on: a slow,
    /// gentle 0.9 s, everything (the page, the artwork, the logo) together.
    static let recede = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.9)
    static let heroAnchor = "details|hero"
    /// The page's left and right margin inside tvOS's own: none, so the words and rows start at
    /// the safe area's edge, 80 pixels in (owner, 27 November: further left).
    static let pageInset: CGFloat = 0
    /// tvOS's own margin at the sides, which the episode row reaches past to the screen's edge.
    static let safeSide: CGFloat = 80
    static let browserAnchor = "details|browser"

    static let restAnchor = "details|rest"
    /// Where the line under a film's hero sits once Down has moved on: near the top, so the
    /// hero's buttons stay in view above the first row.
    static let restPoint = UnitPoint(x: 0.5, y: 0.14)

    /// A card in the rows straight under a film's hero (the cast, then trailers and extras).
    static func isFirstRow(_ key: String?) -> Bool {
        guard let key else { return false }
        return key.hasPrefix("cast|") || key.hasPrefix("extra|")
    }

    /// Play's focus key: the page opens on it, as the reference does.
    static let playKey = "hero|play"

    /// The hero's buttons: Play, or the others (which carry no key).
    static func isHero(_ key: String?) -> Bool { key == nil || key == playKey }

    static func isBrowser(_ key: String?) -> Bool {
        guard let key else { return false }
        return key.hasPrefix("season|") || key.hasPrefix("ep|")
    }


    /// The season tabs over one row of a season's episodes, as the reference design has them:
    /// moving along the tabs shows that season, coming into them lands on the season showing,
    /// and the focused episode shows its overview under it.
    /// The season showing's episode to watch next: one part-way through, else the first not
    /// watched, else the first. Down from the hero lands on it.
    private var seasonNextUp: Item? {
        guard seasons.indices.contains(season) else { return nil }
        let eps = seasons[season].episodes
        return eps.first { $0.available && $0.resumeMs > 0 } ?? eps.first { $0.available && !$0.watched } ?? eps.first
    }

    private var episodes: some View {
        VStack(alignment: .leading, spacing: 20) {
            ScrollView(.horizontal) {
                HStack(spacing: 20) {
                    ForEach(Array(seasons.enumerated()), id: \.element.id) { index, s in
                        Button(s.name.isEmpty ? L("details.season", s.seasonNumber) : s.name) { season = index }
                            .buttonStyle(SeasonTabStyle(chosen: index == season))
                            .focused($focused, equals: "season|\(index)")
                            // Holding Select on a season marks all its episodes, as Plex's season menu.
                            .contextMenu {
                                if s.markable {
                                    Button { markSeason(s, watched: !s.watched) } label: {
                                        Label(s.watched ? L("actions.season_unwatched") : L("actions.season_watched"),
                                              systemImage: s.watched ? "eye.slash" : "checkmark.circle")
                                    }
                                }
                                if browse.queuesUsable && shuffleCandidates(s).count > 1 {
                                    Button { shuffle(s) } label: {
                                        Label(L("actions.shuffle_season"), systemImage: "shuffle")
                                    }
                                }
                                if !s.isUnplaced {
                                    Button { toggleMissing(on: s) } label: {
                                        Label(showMissing ? L("actions.hide_missing") : L("actions.show_missing"),
                                              systemImage: showMissing ? "eye.slash" : "eye")
                                    }
                                }
                            }
                    }
                }
                .padding(.vertical, 12)
            }
            .scrollClipDisabled()
            // Down from Play lands here, on the season showing, as Android's page (owner,
            // 27 November); the tabs peek in under the hero.
            .focusSection()
            if seasons.indices.contains(season) {
                // The row runs to the screen's edge, so a sliver of the fifth episode shows past
                // the fourth (a lazy row builds only what's inside its own frame).
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: EpisodeCard.spacing) {
                        ForEach(seasons[season].episodes) { ep in
                            EpisodeCard(episode: ep, focus: $focused, focusKey: "ep|" + ep.id,
                                        unplaced: seasons[season].isUnplaced) {
                                play(PlayRequest(item: ep, startMs: ep.resumeMs))
                            }
                        }
                    }
                    .padding(.vertical, 24)
                    .padding(.horizontal, Self.pageInset + Self.safeSide)
                }
                .scrollClipDisabled()
                .padding(.horizontal, -(Self.pageInset + Self.safeSide))
                .id(season) // another season starts at its first episode
            }
        }
        .id(Self.browserAnchor)
    }

    /// Marks every episode of a season watched or unwatched, then reads the page (and Home) again.
    private func markSeason(_ s: Season, watched: Bool) {
        guard let api = app.api else { return }
        let id = itemId
        Task {
            do {
                try await api.setPlayed(seriesId: id, seasonNumber: s.seasonNumber, watched)
                keepSeason = s.seasonNumber
                ArcLogApp.debug("title action done: season \(watched ? "watched" : "unwatched")")
                browse.changed()
            } catch let error as APIError where error.status == 401 {
                app.tokenRefused()
            } catch {
                ArcLogApp.warn("title action season watched failed: \(type(of: error))")
            }
        }
    }

    /// The episodes Shuffle plays: a season's on disk, or the show's (its order's seasons, then
    /// specials). Not the Not in This Order tab, which has no place in the order.
    private func shuffleCandidates(_ s: Season?) -> [Item] {
        if let s { return s.isUnplaced ? [] : s.episodes.filter(\.available) }
        let ordered = seasons.filter { $0.seasonNumber > 0 } + seasons.filter { $0.seasonNumber == 0 }
        return ordered.flatMap(\.episodes).filter(\.available)
    }

    /// Shuffle (the show) or Shuffle Season: a new queue in a random order, playing its first.
    private func shuffle(_ s: Season?) {
        guard let api = app.api else { return }
        let ids = shuffleCandidates(s).map(\.id)
        let browse = browse
        Task {
            let entry = await browse.withQueue { await $0.startShuffled(api, ids) }
            guard let entry, let first = entry.item else {
                ArcLogApp.warn("shuffling \(s == nil ? "a show" : "a season") failed")
                browse.note(L("queue.shuffle_failed"))
                return
            }
            ArcLogApp.debug("shuffled \(ids.count) episodes")
            play(PlayRequest(item: first, startMs: 0, queueEntry: entry.id))
        }
    }

    /// Shows or hides the missing episodes, staying on the season the menu was opened on (seasons
    /// with only missing episodes may appear in front of it).
    private func toggleMissing(on s: Season) {
        keepSeason = s.seasonNumber
        showMissing.toggle()
        ArcLogApp.debug("missing episodes \(showMissing ? "shown" : "hidden")")
    }

    private func load() async {
        guard let api = app.api else { return }
        do {
            item = try await api.item(itemId)
            if !shown.isEpisode {
                // More Like This is extra: the page shows without it.
                similar = (try? await api.similar(itemId)) ?? similar
            }
            if shown.isSeries {
                // The order's seasons, then "Not in This Order" for episodes the order doesn't place.
                seasons = try await api.seasons(seriesId: itemId, missing: showMissing).tabs(unplacedName: L("details.not_in_order"))
                if !landed, let id = episodeId, let at = seasons.firstIndex(where: { $0.episodes.contains { $0.id == id } }) {
                    // Opened from an episode: its season, then the episode itself.
                    landed = true
                    season = at
                    landing = id
                } else if let kept = keepSeason, let at = seasons.firstIndex(where: { $0.seasonNumber == kept }) {
                    // Read again after a season was marked: stay on it rather than move to the next episode's.
                    keepSeason = nil
                    season = at
                } else if let next = nextEpisode, let at = seasons.firstIndex(where: { $0.seasonNumber == next.seasonNumber }) {
                    season = at
                }
            }
        } catch let error as APIError where error.status == 401 {
            app.tokenRefused()
        } catch is CancellationError {
        } catch {
            ArcLogApp.warn("title page failed to load: \(type(of: error))")
            problem = L("common.unreachable")
        }
    }
}

/// An episode in a season: its still (with its length, or how far through), its number and
/// name, and its overview while it has the focus. One that hasn't aired yet is dimmed with the day
/// it releases; it can take the focus but doesn't play.
struct EpisodeCard: View {
    @Environment(AppModel.self) private var app
    let episode: Item
    var focus: FocusState<String?>.Binding
    let focusKey: String
    /// Outside the show's order ("Not in This Order"): the order gives it no number, so none shows.
    var unplaced = false
    let action: () -> Void

    /// Four episodes and a little of the fifth across the screen, as Android's (400 by 225 with
    /// 40 between them, from the page's margin).
    static let size = CGSize(width: 400, height: 225)
    static let spacing: CGFloat = 40
    private var size: CGSize { Self.size }

    /// Its running time, or what's left of it part-way through.
    private var length: String? {
        let card = MediaCard(item: episode)
        if card.progress != nil, let left = card.minutesLeft { return L("card.minutes_left", left) }
        guard episode.available, let m = episode.runtimeMin, m > 0 else { return nil }
        return runtimeText(m)
    }

    var body: some View {
        let card = MediaCard(item: episode)
        let art = card.spoilerSafe(app.hideSpoilers)
        let releases = episode.upcomingRelease()
        VStack(alignment: .leading, spacing: 10) {
            Button { if episode.available { action() } } label: {
                ZStack(alignment: .bottomLeading) {
                    ArtworkImage(path: art.thumb)
                        .frame(width: size.width, height: size.height)
                        .blur(radius: art.blurred ? 24 : 0).clipped()
                        .opacity(episode.available ? 1 : 0.25)
                    // Not out yet: the day it releases. Out, but with no file (Show Missing
                    // Episodes): says so.
                    if !episode.available {
                        Label(releases.map { L("details.releases", Item.releaseDay($0)) } ?? L("details.not_on_disk"),
                              systemImage: releases == nil ? "externaldrive.badge.xmark" : "clock")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(.black.opacity(0.6)))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if let progress = card.progress {
                        ResumeStrip(fraction: progress, minutesLeft: card.minutesLeft)
                    }
                    WatchBadge(item: episode)
                }
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: cardCorner, style: .continuous))
            }
            .buttonStyle(.card)
            .focused(focus, equals: focusKey)
            // As Android's and the other Arc apps' episode cards: the number, the name, three
            // lines of the description on every card, then its length (or what's left of it).
            VStack(alignment: .leading, spacing: 4) {
                if !unplaced, let code = episode.episodeCodeText {
                    Text(code).font(.caption.weight(.semibold)).foregroundStyle(ArcColor.muted)
                }
                Text(episode.title).font(.callout.weight(.semibold)).lineLimit(1)
                // Kept the same height on every card, so the names below line up.
                Text(episode.overview(hidingSpoilers: app.hideSpoilers) ?? " ").font(.caption).foregroundStyle(.white.opacity(0.7))
                    .lineLimit(3, reservesSpace: true)
                if let length {
                    Text(length).font(.caption).foregroundStyle(ArcColor.muted)
                }
            }
            .frame(width: size.width, alignment: .leading)
            .belowLiftedCard(focus.wrappedValue == focusKey)
        }
    }
}

/// A glass card at the foot of a title's page (About, Details, Crew, Playback). It takes the focus
/// so the page can scroll down to it with the remote.
struct InfoCard<Content: View>: View {
    let title: String?
    var width: CGFloat = 340
    @ViewBuilder let content: () -> Content
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title { Text(title).font(.title3.weight(.semibold)) }
            content()
        }
        .padding(26)
        .frame(width: width, alignment: .topLeading)
        .frame(minHeight: 300, alignment: .topLeading)
        .arcGlassPanel(cornerRadius: 28)
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(focused ? 0.9 : 0), lineWidth: 3))
        .scaleEffect(focused ? 1.04 : 1)
        .animation(.easeOut(duration: 0.15), value: focused)
        .focusable()
        .focused($focused)
    }
}

/// A season tab, as the reference draws them: plain words, the chosen season in a soft glass
/// capsule, and the focused one white with black words.
struct SeasonTabStyle: ButtonStyle {
    let chosen: Bool
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(chosen || isFocused ? .semibold : .medium))
            .padding(.horizontal, 22).padding(.vertical, 10)
            .foregroundStyle(isFocused ? Color.black : chosen ? Color.white : Color.white.opacity(0.7))
            .background {
                if isFocused {
                    Capsule().fill(.white)
                } else if chosen {
                    GlassFill(shape: Capsule()).overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 1.5))
                }
            }
            .scaleEffect(isFocused ? 1.06 : configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}
