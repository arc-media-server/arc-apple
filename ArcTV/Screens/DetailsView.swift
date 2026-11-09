import ArcKit
import SwiftUI

/// What the player is asked to play, and from where in the file.
struct PlayRequest: Identifiable, Hashable {
    let item: Item
    let startMs: Int64
    /// Played in a Watch Together room: the room decides where and whether it plays.
    var together = false
    var id: String { item.id + "@\(startMs)" + (together ? "|together" : "") }
}

/// A title's page: its background, logo or title, details, Play and its actions; a show's seasons
/// and episodes; then its cast, collections and More Like This, as Plex's page.
struct DetailsView: View {
    @Environment(AppModel.self) private var app
    @Environment(Browse.self) private var browse
    @Environment(\.openRoute) private var openRoute
    let itemId: String
    let initial: Item

    @State private var item: Item?
    @State private var similar: [Item] = []
    @FocusState private var focused: String?
    @State private var seasons: [Season] = []
    @State private var season = 0
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
                // The episode browser: the artwork slides up and away, on the page's own clock.
                .offset(y: receded ? -1200 : 0)
                .opacity(receded ? 0 : 1)
                .animation(Self.recede, value: receded)
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 28) {
                        hero
                            // Hidden while browsing a show's episodes, as the reference does: a
                            // mask rather than opacity, so Up from the season tabs still reaches
                            // its buttons (tvOS won't focus a fully transparent view).
                            // Larger than the hero, so a focused button's lift and shadow aren't cut off.
                            .mask(Rectangle().opacity(browsing || !entered ? 0 : 1).padding(-80))
                            .animation(browsing ? .easeOut(duration: 0.3) : Self.recede, value: browsing)
                            .id(Self.heroAnchor)
                        if !seasons.isEmpty {
                            episodes
                        } else {
                            // A film's hero has nothing peeking under it, as the reference: the
                            // next row starts just below the screen, and Down scrolls to it.
                            Color.clear.frame(height: 1).id(Self.restAnchor)
                            Color.clear.frame(height: 150).accessibilityHidden(true)
                        }
                        // The cast first, above every other row (owner, 7 November).
                        if !actors.isEmpty { cast }
                        if !shown.extras.isEmpty { extras }
                        if !similar.isEmpty { related }
                        if !shown.collections.isEmpty { collections }
                        infoCards
                    }
                    .padding(.horizontal, 80)
                    .padding(.bottom, 60)
                }
                .defaultFocus($focused, Self.playKey)
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
                    if Self.isHero(old), let new, new.hasPrefix("ep|"), let next = seasonNextUp, new != "ep|" + next.id {
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
                        withAnimation(Self.recede) {
                            receded = true
                            proxy.scrollTo(Self.browserAnchor, anchor: Self.tabsAnchor)
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
            if !seasons.isEmpty {
                TitleLogo(path: shown.images?.logo, title: shown.title)
                    .frame(maxWidth: 560, maxHeight: 150)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 50)
                    // It trails in from a little lower, and leaves quicker than it came, so it's
                    // gone before the hero is back.
                    .offset(y: browsing ? 0 : 100)
                    .opacity(browsing ? 1 : 0)
                    .animation(browsing ? Self.recede : .easeInOut(duration: 0.35), value: browsing)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .onAppear {
            guard !entered else { return }
            withAnimation(.easeOut(duration: 0.4).delay(0.35)) { entered = true }
        }
        .task(id: browse.changes) { await load() }
        .task(id: paletteSource) {
            // The server keeps each backdrop's colours; an older server without them, or a title
            // without artwork, keeps Arc's grey blend.
            guard let id = paletteSource, let api = app.api,
                  let colors = try? await api.palette(id).background else { return }
            wash = colors.map(Color.init)
        }
        .fullScreenCover(item: $extra) { ExtraPlayerScreen(extra: $0) }
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
                    Text(e.title).font(.caption.weight(.semibold)).lineLimit(1).frame(width: 384, alignment: .leading)
                    Text(extraKind(e)).font(.caption2).foregroundStyle(ArcColor.muted)
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
                if let overview = shown.overview {
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
        .frame(minHeight: 860, alignment: .bottomLeading)
    }

    /// The year (or a show's first year) and the length.
    private var facts: String {
        var parts: [String] = []
        if let year = shown.year { parts.append(String(year)) }
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
        section(L("details.related")) {
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
            if let overview = shown.overview, !overview.isEmpty {
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

    /// A show's Play: the first episode not yet watched (or part-watched), else the first.
    private var nextEpisode: Item? {
        let all = seasons.filter { $0.seasonNumber > 0 }.flatMap(\.episodes) + seasons.filter { $0.seasonNumber == 0 }.flatMap(\.episodes)
        let available = all.filter(\.available)
        return available.first { !$0.watched } ?? available.first
    }

    /// The one clock the move between a show's overview and its episodes runs on: a slow,
    /// gentle 0.9 s, everything (the page, the artwork, the logo) together.
    static let recede = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.9)
    static let heroAnchor = "details|hero"
    static let browserAnchor = "details|browser"
    /// Where the season tabs sit while browsing episodes: a quarter of the way down the screen,
    /// leaving the top for the show's logo (scrollTo lines this point of the tabs up with the
    /// same point of the screen).
    static let tabsAnchor = UnitPoint(x: 0.5, y: 0.25)

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

    /// Whether the season tabs or an episode has the focus (the episode browser is up).
    private var browsing: Bool { Self.isBrowser(focused) }

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
                    }
                }
                .padding(.vertical, 12)
            }
            .scrollClipDisabled()
            .focusSection()
            // Out of reach from the hero's buttons, so Down from Play goes straight into the
            // episodes (as the reference does); Up from the episodes reaches them.
            .disabled(Self.isHero(focused))
            // On the hero the tabs are folded away, so the top of the episode row peeks in at the
            // bottom of the screen (as the reference does); Down brings them back with the
            // episodes. A mask rather than opacity, as for the hero.
            .frame(maxHeight: browsing ? nil : 0, alignment: .top)
            .mask(Rectangle().opacity(browsing ? 1 : 0).padding(-40))
            .animation(Self.recede, value: browsing)
            .id(Self.browserAnchor)
            if seasons.indices.contains(season) {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 40) {
                        ForEach(seasons[season].episodes) { ep in
                            EpisodeCard(episode: ep, focus: $focused, focusKey: "ep|" + ep.id,
                                        showsOverview: focused == "ep|" + ep.id) {
                                play(PlayRequest(item: ep, startMs: ep.resumeMs))
                            }
                        }
                    }
                    .padding(.vertical, 24)
                }
                .scrollClipDisabled()
                .id(season) // another season starts at its first episode
            }
        }
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
                seasons = try await api.seasons(seriesId: itemId).seasons
                if let next = nextEpisode, let at = seasons.firstIndex(where: { $0.seasonNumber == next.seasonNumber }) { season = at }
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
    let episode: Item
    var focus: FocusState<String?>.Binding
    let focusKey: String
    var showsOverview = false
    let action: () -> Void

    private var size: CGSize { CardStyle.thumb.size }

    var body: some View {
        let card = MediaCard(item: episode)
        let releases = episode.upcomingRelease()
        VStack(alignment: .leading, spacing: 10) {
            Button { if episode.available { action() } } label: {
                ZStack(alignment: .bottomLeading) {
                    ArtworkImage(path: episode.images?.primary ?? episode.images?.seriesBackdrop)
                        .frame(width: size.width, height: size.height).clipped()
                        .opacity(episode.available ? 1 : 0.25)
                    if let releases {
                        Label(L("details.releases", Item.releaseDay(releases)), systemImage: "clock")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(.black.opacity(0.6)))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if let progress = card.progress {
                        ResumeStrip(fraction: progress, minutesLeft: card.minutesLeft)
                    } else if episode.available, let m = episode.runtimeMin, m > 0 {
                        Text(runtimeText(m)).font(.callout.weight(.semibold))
                            .shadow(color: .black.opacity(0.7), radius: 4)
                            .padding(16)
                    }
                    if episode.watched {
                        Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.black, .white)
                            .padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: cardCorner, style: .continuous))
            }
            .buttonStyle(.card)
            .focused(focus, equals: focusKey)
            Text(L("card.episode_short", episode.episodeNumber ?? 0, episode.title))
                .font(.callout.weight(.semibold)).lineLimit(1).frame(width: size.width, alignment: .leading)
            // Kept in the layout so the row doesn't jump as the focus moves.
            Text(episode.overview ?? " ").font(.caption).foregroundStyle(.white.opacity(0.8))
                .lineLimit(3, reservesSpace: true).frame(width: size.width, alignment: .leading)
                .opacity(showsOverview ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: showsOverview)
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
