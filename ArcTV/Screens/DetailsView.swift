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
    /// The season tabs: coming into them lands on the season showing.
    @Namespace private var seasonTabs
    @State private var problem: String?
    @State private var extra: Extra?

    private var shown: Item { item ?? initial }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ArtworkImage(path: shown.images?.backdrop ?? shown.images?.seriesBackdrop)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(LinearGradient(colors: [.clear, ArcColor.background.opacity(0.85), ArcColor.background], startPoint: .top, endPoint: .bottom))
                .overlay(LinearGradient(colors: [ArcColor.background.opacity(0.9), .clear], startPoint: .leading, endPoint: .trailing))
                .ignoresSafeArea()
            // While a show's seasons and episodes have the focus the artwork darkens a little and
            // the show's logo sits small and centred at the top, over the season tabs.
            Color.black.opacity(browsing ? 0.35 : 0).ignoresSafeArea().allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.3), value: browsing)
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 28) {
                        hero.id(Self.heroAnchor)
                        if !seasons.isEmpty {
                            // The point the page scrolls to for the episode browser: room above the
                            // season tabs for the logo. (Negative padding keeps it out of the layout.)
                            Color.clear.frame(height: Self.browserLogoRoom).id(Self.browserAnchor)
                                .padding(.top, -Self.browserLogoRoom)
                            episodes
                        }
                        if !shown.extras.isEmpty { extras }
                        if !similar.isEmpty { related }
                        if !actors.isEmpty { cast }
                        if !shown.collections.isEmpty { collections }
                        infoCards
                    }
                    .padding(.horizontal, 80)
                    .padding(.bottom, 60)
                }
                .onChange(of: focused) { old, new in
                    if let new, new.hasPrefix("season|"), let index = Int(new.dropFirst(7)), index != season {
                        // Moving along the season tabs shows that season's episodes; no Select.
                        withAnimation(.easeInOut(duration: 0.2)) { season = index }
                    }
                    let wasBrowsing = Self.isBrowser(old), nowBrowsing = Self.isBrowser(new)
                    if nowBrowsing && !wasBrowsing {
                        withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(Self.browserAnchor, anchor: .top) }
                    } else if !nowBrowsing && old?.hasPrefix("season|") == true && new == nil {
                        // Up from the season tabs is the hero's buttons: back to the top.
                        withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(Self.heroAnchor, anchor: .top) }
                    }
                }
            }
            if !seasons.isEmpty {
                TitleLogo(path: shown.images?.logo, title: shown.title)
                    .frame(maxWidth: 560, maxHeight: 150)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 50)
                    .opacity(browsing ? 1 : 0)
                    .animation(.easeInOut(duration: 0.3), value: browsing)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .task(id: browse.changes) { await load() }
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
            if shown.playable {
                let resume = shown.resumeMs
                Button { play(PlayRequest(item: shown, startMs: resume)) } label: {
                    Label(resume > 0 ? L("details.resume") : L("details.play"), systemImage: "play.fill")
                }
                .arcGlassButton(prominent: true)
                if resume > 0 {
                    Button { play(PlayRequest(item: shown, startMs: 0)) } label: {
                        Label(L("details.from_beginning"), systemImage: "arrow.counterclockwise")
                    }
                    .roundIconButton()
                }
            } else if let next = nextEpisode {
                Button { play(PlayRequest(item: next, startMs: next.resumeMs)) } label: {
                    Label(next.resumeMs > 0 ? L("details.resume_episode", next.seasonNumber ?? 0, next.episodeNumber ?? 0)
                          : L("details.play_episode", next.seasonNumber ?? 0, next.episodeNumber ?? 0), systemImage: "play.fill")
                }
                .arcGlassButton(prominent: true)
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
                PersonButton(name: credit.name, detail: credit.character ?? roleName(credit.role), image: credit.image) {
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
            (L("details.studio"), shown.studio ?? ""),
        ].filter { !$0.1.isEmpty }
        let playback = playbackLines(file)
        let about = (shown.tagline?.isEmpty == false ? shown.tagline : nil) ?? (shown.isEpisode ? shown.title : nil)
        return VStack(alignment: .leading, spacing: 24) {
            Text(L("details.about")).font(.title3.weight(.semibold))
            if let overview = shown.overview, !overview.isEmpty {
                InfoCard(title: nil, width: 1100) {
                    if let about { Text(about).font(.headline) }
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

    /// What the file is: its video, its main audio and its size.
    private func playbackLines(_ file: MediaFile?) -> [(String, String)] {
        guard let file else { return [] }
        var out: [(String, String)] = []
        if let v = file.streams.first(where: { $0.kind == "video" }) {
            let parts = [Quality.resolution(v), Quality.hdr(v), v.codec.isEmpty ? nil : v.codec.uppercased()].compactMap { $0 }
            if !parts.isEmpty { out.append((L("details.video"), parts.joined(separator: " · "))) }
        }
        let audios = file.streams.filter { $0.kind == "audio" }
        if let a = audios.first(where: \.isDefault) ?? audios.first {
            let parts = [Quality.audioCodec(a), Quality.channels(a.channels), Quality.objectAudio(a)].compactMap { $0 }
            if !parts.isEmpty { out.append((L("details.audio"), parts.joined(separator: " "))) }
        }
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
        if let server = app.serverName, !server.isEmpty { out.insert((L("details.server"), server), at: 0) }
        if let profile = app.profile?.name { out.insert((L("details.profile"), profile), at: min(1, out.count)) }
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

    static let heroAnchor = "details|hero"
    static let browserAnchor = "details|browser"
    /// Room above the season tabs for the show's logo while browsing episodes.
    static let browserLogoRoom: CGFloat = 230

    static func isBrowser(_ key: String?) -> Bool {
        guard let key else { return false }
        return key.hasPrefix("season|") || key.hasPrefix("ep|")
    }

    /// Whether the season tabs or an episode has the focus (the episode browser is up).
    private var browsing: Bool { Self.isBrowser(focused) }

    /// The season tabs over one row of a season's episodes, as the reference design has them:
    /// moving along the tabs shows that season, coming into them lands on the season showing,
    /// and the focused episode shows its overview under it.
    private var episodes: some View {
        VStack(alignment: .leading, spacing: 20) {
            ScrollView(.horizontal) {
                HStack(spacing: 20) {
                    ForEach(Array(seasons.enumerated()), id: \.element.id) { index, s in
                        Button(s.name.isEmpty ? L("details.season", s.seasonNumber) : s.name) { season = index }
                            .arcGlassButton(prominent: index == season)
                            .focused($focused, equals: "season|\(index)")
                            .prefersDefaultFocus(index == season, in: seasonTabs)
                    }
                }
                .padding(.vertical, 12)
            }
            .scrollClipDisabled()
            .focusSection()
            .focusScope(seasonTabs)
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
                        .opacity(episode.available ? 1 : 0.35)
                    if let releases {
                        Label(L("details.releases", releases.formatted(.dateTime.day().month(.abbreviated))), systemImage: "clock")
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
