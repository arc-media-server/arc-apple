import ArcKit
import SwiftUI

extension CardStyle {
    var size: CGSize {
        switch self {
        case .poster: return CGSize(width: 220, height: 330)
        case .thumb: return CGSize(width: 400, height: 225)
        case .backdrop: return CGSize(width: 400, height: 300)
        }
    }
}

/// A title on a row, in its row's style. The tvOS card button gives the lift and shine on focus.
struct MediaCardView: View {
    let card: MediaCard
    let style: CardStyle
    var seasonPosters = false
    /// Where the row keeps which card has the focus (Home's backdrop follows it).
    var focus: FocusState<String?>.Binding
    let focusKey: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: action) {
                ZStack(alignment: .bottomLeading) {
                    ArtworkImage(path: card.art(style, seasonPosters: seasonPosters))
                        .frame(width: style.size.width, height: style.size.height)
                        .clipped()
                    if style == .backdrop, let logo = card.logo {
                        ArtworkImage(path: logo, contentMode: .fit)
                            .frame(width: style.size.width * 0.6, height: style.size.height * 0.3)
                            .padding(20)
                    }
                    if let progress = card.progress {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(.black.opacity(0.5))
                                Rectangle().fill(ArcColor.accent).frame(width: geo.size.width * progress)
                            }
                        }
                        .frame(height: 6)
                    }
                    if card.item.watched {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, ArcColor.accentStrong)
                            .padding(12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
                .frame(width: style.size.width, height: style.size.height)
            }
            .buttonStyle(.card)
            .focused(focus, equals: focusKey)
            .contextMenu { TitleActions(item: card.item) }
            if style != .poster {
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.item.isEpisode ? card.item.seriesTitle ?? card.item.title : card.item.title).font(.callout).lineLimit(1)
                    if let sub = subtitle { Text(sub).font(.caption).foregroundStyle(ArcColor.muted).lineLimit(1) }
                }
                .frame(width: style.size.width, alignment: .leading)
            }
        }
    }

    private var subtitle: String? {
        let item = card.item
        if let season = card.seasonNumber, card.newEpisodes > 0 { return L("card.new_episodes", season, card.newEpisodes) }
        if item.isEpisode, let s = item.seasonNumber, let e = item.episodeNumber { return L("card.episode", s, e, item.title) }
        return item.year.map(String.init)
    }
}

/// A title's actions, from holding Select on its card (Plex's context menu) and on its page:
/// play, watched or not, the Watchlist, and an episode's show.
struct TitleActions: View {
    @Environment(AppModel.self) private var app
    @Environment(Browse.self) private var browse
    @Environment(\.openRoute) private var openRoute
    let item: Item
    var onPage = false

    var body: some View {
        if !onPage && item.playable {
            Button { browse.play(PlayRequest(item: item, startMs: item.resumeMs)) } label: {
                Label(item.resumeMs > 0 ? L("details.resume") : L("details.play"), systemImage: "play.fill")
            }
            if item.resumeMs > 0 {
                Button { browse.play(PlayRequest(item: item, startMs: 0)) } label: {
                    Label(L("details.from_beginning"), systemImage: "arrow.counterclockwise")
                }
            }
        }
        if item.playable || item.isSeries {
            Button { act("watched") { try await $0.setPlayed(item.id, !item.watched) } } label: {
                Label(item.watched ? L("actions.mark_unwatched") : L("actions.mark_watched"),
                      systemImage: item.watched ? "eye.slash" : "checkmark.circle")
            }
        }
        if item.kind == "movie" || item.isSeries {
            let on = item.userData?.watchlisted == true
            Button { act("watchlist") { try await $0.setWatchlisted(item.id, !on) } } label: {
                Label(on ? L("actions.watchlist_remove") : L("actions.watchlist_add"), systemImage: on ? "bookmark.slash" : "bookmark")
            }
        }
        if !onPage, item.isEpisode, let show = item.parentId {
            Button { openRoute(.item(Item(id: show, kind: "series", title: item.seriesTitle ?? item.title))) } label: {
                Label(L("actions.go_to_show"), systemImage: "tv")
            }
        }
    }

    private func act(_ what: String, _ call: @escaping (ArcAPI) async throws -> Void) {
        guard let api = app.api else { return }
        Task {
            do {
                try await call(api)
                ArcLogApp.debug("title action done: \(what)")
                browse.changed()
            } catch let error as APIError where error.status == 401 {
                app.tokenRefused()
            } catch {
                ArcLogApp.warn("title action \(what) failed: \(type(of: error))")
            }
        }
    }
}
