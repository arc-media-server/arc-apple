import ArcKit
import SwiftUI

/// What the player is asked to play, and from where in the file.
struct PlayRequest: Identifiable, Hashable {
    let item: Item
    let startMs: Int64
    var id: String { item.id + "@\(startMs)" }
}

/// A title's page: its background, logo or title, details and Play; a show's seasons and episodes.
struct DetailsView: View {
    @Environment(AppModel.self) private var app
    let itemId: String
    let initial: Item
    let play: (PlayRequest) -> Void

    @State private var item: Item?
    @State private var seasons: [Season] = []
    @State private var season = 0
    @State private var problem: String?

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
                    Spacer(minLength: 360)
                    TitleLogo(path: shown.images?.logo, title: shown.title)
                    Text(meta).foregroundStyle(ArcColor.muted)
                    if let overview = shown.overview {
                        Text(overview).frame(maxWidth: 1100, alignment: .leading).lineLimit(4)
                    }
                    if let problem { Text(problem).foregroundStyle(ArcColor.error) }
                    buttons
                    if !seasons.isEmpty { episodes }
                }
                .padding(.horizontal, 80)
                .padding(.bottom, 60)
            }
        }
        .task(id: itemId) { await load() }
    }

    private var meta: String {
        var parts: [String] = []
        if let year = shown.year { parts.append(String(year)) }
        if let rating = shown.contentRating { parts.append(rating) }
        if let minutes = shown.runtimeMin, minutes > 0 { parts.append(L("details.runtime", minutes / 60, minutes % 60)) }
        if !shown.genres.isEmpty { parts.append(shown.genres.prefix(3).joined(separator: ", ")) }
        return parts.joined(separator: "  ·  ")
    }

    @ViewBuilder private var buttons: some View {
        HStack(spacing: 32) {
            if shown.playable {
                let resume = shown.resumeMs
                Button { play(PlayRequest(item: shown, startMs: resume)) } label: {
                    Label(resume > 0 ? L("details.resume") : L("details.play"), systemImage: "play.fill")
                }
                if resume > 0 {
                    Button { play(PlayRequest(item: shown, startMs: 0)) } label: {
                        Label(L("details.from_beginning"), systemImage: "arrow.counterclockwise")
                    }
                }
            } else if let next = nextEpisode {
                Button { play(PlayRequest(item: next, startMs: next.resumeMs)) } label: {
                    Label(next.resumeMs > 0 ? L("details.resume_episode", next.seasonNumber ?? 0, next.episodeNumber ?? 0)
                          : L("details.play_episode", next.seasonNumber ?? 0, next.episodeNumber ?? 0), systemImage: "play.fill")
                }
            }
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
                            .tint(index == season ? ArcColor.accentStrong : nil)
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
        VStack(alignment: .leading, spacing: 10) {
            Button(action: action) {
                ZStack(alignment: .bottomLeading) {
                    ArtworkImage(path: episode.images?.primary).frame(width: 400, height: 225).clipped()
                    if let card = Optional(MediaCard(item: episode)), let progress = card.progress {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(.black.opacity(0.5))
                                Rectangle().fill(ArcColor.accent).frame(width: geo.size.width * progress)
                            }
                        }
                        .frame(height: 6)
                    }
                }
                .frame(width: 400, height: 225)
            }
            .buttonStyle(.card)
            .disabled(!episode.available)
            Text(L("card.episode_short", episode.episodeNumber ?? 0, episode.title)).font(.callout).lineLimit(1).frame(width: 400, alignment: .leading)
        }
    }
}
