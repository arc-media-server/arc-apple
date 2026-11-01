import ArcKit
import SwiftUI

/// What the player is asked to play, and from where in the file.
struct PlayRequest: Identifiable, Hashable {
    let item: Item
    let startMs: Int64
    var id: String { item.id + "@\(startMs)" }
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
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 28) {
                    hero
                    if !seasons.isEmpty { episodes }
                    if !shown.extras.isEmpty { extras }
                    if !similar.isEmpty { related }
                    if !actors.isEmpty { cast }
                    if !shown.collections.isEmpty { collections }
                    infoCards
                }
                .padding(.horizontal, 80)
                .padding(.bottom, 60)
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
                    ForEach(Quality.badges(Quality.file(of: shown)), id: \.self) { OutlinedBadge(text: $0) }
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

    /// About, Details, Crew and Playback as glass cards at the foot of the page.
    /// (Arc's ratings are paused, so there's no Ratings card.)
    private var infoCards: some View {
        let file = Quality.file(of: shown)
        let details: [(String, String)] = [
            (L("details.released"), shown.releaseDate.flatMap(releaseDate) ?? shown.year.map(String.init) ?? ""),
            (L("details.studio"), shown.studio ?? ""),
            (L("details.original_title"), shown.originalTitle.flatMap { $0 == shown.title ? nil : $0 } ?? ""),
        ].filter { !$0.1.isEmpty }
        let crewLines: [(String, String)] = [
            (L("details.directed_by"), ListFormatter.localizedString(byJoining: crew("director"))),
            (L("details.written_by"), ListFormatter.localizedString(byJoining: crew("writer"))),
        ].filter { !$0.1.isEmpty }
        let playback = playbackLines(file)
        return ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 30) {
                if let overview = shown.overview, !overview.isEmpty {
                    InfoCard(title: L("details.about"), width: 620) {
                        if let tagline = shown.tagline, !tagline.isEmpty { Text(tagline).font(.callout.weight(.semibold)) }
                        Text(overview).font(.caption).foregroundStyle(.white.opacity(0.85)).lineLimit(9)
                    }
                }
                if !details.isEmpty { InfoCard(title: L("details.details")) { lines(details) } }
                if !crewLines.isEmpty { InfoCard(title: L("details.crew")) { lines(crewLines) } }
                if !playback.isEmpty { InfoCard(title: L("details.playback")) { lines(playback) } }
            }
            .padding(.vertical, 24)
        }
        .scrollClipDisabled()
    }

    private func lines(_ pairs: [(String, String)]) -> some View {
        ForEach(pairs, id: \.0) { pair in
            VStack(alignment: .leading, spacing: 2) {
                Text(pair.0).font(.caption2).foregroundStyle(ArcColor.muted)
                Text(pair.1).font(.caption.weight(.semibold)).lineLimit(2)
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
        if let size = file.size, size > 0 {
            out.append((L("details.size"), ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))
        }
        if let edition = file.edition, !edition.isEmpty { out.append((L("details.edition"), edition)) }
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

    private var episodes: some View {
        VStack(alignment: .leading, spacing: 24) {
            ScrollView(.horizontal) {
                HStack(spacing: 24) {
                    ForEach(Array(seasons.enumerated()), id: \.element.id) { index, s in
                        Button(s.name.isEmpty ? L("details.season", s.seasonNumber) : s.name) { season = index }
                            .arcGlassButton(prominent: index == season)
                    }
                }
                .padding(.vertical, 12)
            }
            .scrollClipDisabled()
            if seasons.indices.contains(season) {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 40) {
                        ForEach(seasons[season].episodes) { ep in
                            EpisodeCard(episode: ep) { play(PlayRequest(item: ep, startMs: ep.resumeMs)) }
                        }
                    }
                    .padding(.vertical, 24)
                }
                .scrollClipDisabled()
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

/// An episode in a season: its still, number and title, with how far through.
struct EpisodeCard: View {
    let episode: Item
    let action: () -> Void

    var body: some View {
        let card = MediaCard(item: episode)
        VStack(alignment: .leading, spacing: 10) {
            Button(action: action) {
                ZStack(alignment: .bottomLeading) {
                    ArtworkImage(path: episode.images?.primary).frame(width: 384, height: 216).clipped()
                    if let progress = card.progress { ProgressBar(fraction: progress).padding(12) }
                    if episode.watched {
                        Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.black, .white)
                            .padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
                .frame(width: 384, height: 216)
                .clipShape(RoundedRectangle(cornerRadius: cardCorner, style: .continuous))
            }
            .buttonStyle(.card)
            .disabled(!episode.available)
            Text(L("card.episode_short", episode.episodeNumber ?? 0, episode.title)).font(.caption.weight(.semibold)).lineLimit(1).frame(width: 384, alignment: .leading)
            if let overview = episode.overview {
                Text(overview).font(.caption2).foregroundStyle(ArcColor.muted).lineLimit(2).frame(width: 384, alignment: .leading)
            }
        }
    }
}

/// A glass card at the foot of a title's page (About, Details, Crew, Playback). It takes the focus
/// so the page can scroll down to it with the remote.
struct InfoCard<Content: View>: View {
    let title: String
    var width: CGFloat = 340
    @ViewBuilder let content: () -> Content
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
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
