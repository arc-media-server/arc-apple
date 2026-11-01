import ArcKit
import SwiftUI

/// A full-screen hero for the focused title (its background, logo or name, details and glass
/// Play, Watchlist and Info buttons) with rows of titles beneath, the first one peeking up: Home,
/// and a library's Recommended. `header` sits above the hero (a library's pill bar).
struct HeroRows<Header: View>: View {
    @Environment(AppModel.self) private var app
    @Environment(Browse.self) private var browse
    @Environment(\.openRoute) private var openRoute
    let rows: [LoadedRow]
    /// Room left at the top of the hero for the floating header.
    var headerHeight: CGFloat = 0
    @ViewBuilder var header: () -> Header
    /// The title the hero shows: the focused card, or the one last focused.
    @State private var hero: MediaCard?
    @FocusState private var focused: String?
    /// The header floats over the top of the page (as Plozz's pill bar) while the hero or the
    /// first row has the focus, and fades away further down so it doesn't cover a row.
    @State private var headerShown = true

    var body: some View {
        ZStack(alignment: .topLeading) {
            backdrop
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 44) {
                    if let hero { heroDetails(hero) }
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 16) {
                            Text(row.title).font(.headline).padding(.horizontal, 80)
                            ScrollView(.horizontal) {
                                LazyHStack(alignment: .top, spacing: 36) {
                                    ForEach(row.cards) { card in
                                        MediaCardView(card: card, style: row.style, seasonPosters: row.seasonPosters,
                                                      focus: $focused, focusKey: row.id + "|" + card.id) { open(card) }
                                    }
                                }
                                .padding(.horizontal, 80)
                                .padding(.vertical, 20)
                            }
                            .scrollClipDisabled()
                        }
                    }
                }
                .padding(.top, headerHeight)
                .padding(.bottom, 60)
            }
            header()
                .opacity(headerShown ? 1 : 0)
                .animation(.easeInOut(duration: 0.25), value: headerShown)
        }
        // Focus starts on the first title, as Plex's Home and library pages.
        .onAppear { focusFirst() }
        .onChange(of: rows.first?.cards.first?.id) { _, _ in focusFirst() }
        .onChange(of: focused) { _, _ in
            if let card = focusedCard { hero = card }
            // Focus outside the cards and the hero's buttons is in the header itself.
            if let key = focused, !key.hasPrefix("hero|") {
                headerShown = key.hasPrefix((rows.first?.id ?? "") + "|")
            } else {
                headerShown = true
            }
        }
    }

    private func focusFirst() {
        guard focused == nil, let row = rows.first, let card = row.cards.first else { return }
        if hero == nil { hero = card }
        Task { @MainActor in focused = row.id + "|" + card.id }
    }

    /// The hero's words and buttons, over the background; the first row starts just under it.
    private func heroDetails(_ card: MediaCard) -> some View {
        let item = card.item
        return VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 0)
            if let logo = card.logo {
                TitleLogo(path: logo, title: item.isEpisode ? item.seriesTitle ?? item.title : item.title)
                    .frame(maxWidth: 560, maxHeight: 180, alignment: .leading)
            } else {
                Text(item.isEpisode ? item.seriesTitle ?? item.title : item.title).font(.system(size: 64, weight: .bold)).lineLimit(2)
            }
            // Plozz's hero line: the rating in a box, then the genres; an episode's own line under it.
            HStack(spacing: 12) {
                if let rating = item.contentRating, !rating.isEmpty { OutlinedBadge(text: rating) }
                if let line = genreLine(item) { Text(line) }
            }
            .font(.callout.weight(.medium)).foregroundStyle(.white.opacity(0.85))
            if let line = detailLine(item) {
                Text(line).font(.callout).foregroundStyle(.white.opacity(0.85))
            }
            // Under a header there's no room for the overview: the first row would push the
            // title under the bar. Info has it.
            if headerHeight == 0, let overview = item.overview, !overview.isEmpty {
                Text(overview).font(.callout).foregroundStyle(.white.opacity(0.75)).lineLimit(3).frame(maxWidth: 760, alignment: .leading)
            }
            HStack(spacing: 20) {
                Button { play(card) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "play.fill")
                        if let progress = card.progress, let left = card.minutesLeft {
                            ProgressBar(fraction: progress, color: .black).frame(width: 90)
                            Text(L("card.minutes_short", left))
                        } else {
                            Text(L("details.play"))
                        }
                    }
                }
                .arcGlassButton(prominent: true)
                .focused($focused, equals: "hero|play")
                if item.kind == "movie" || item.isSeries {
                    Button { toggleWatchlist(item) } label: {
                        Label(item.userData?.watchlisted == true ? L("actions.watchlist_remove") : L("actions.watchlist_add"),
                              systemImage: item.userData?.watchlisted == true ? "bookmark.fill" : "bookmark")
                    }
                    .roundIconButton()
                    .focused($focused, equals: "hero|watchlist")
                }
                Button { openRoute(.item(pageItem(item))) } label: {
                    Label(L("home.more_info"), systemImage: "info.circle")
                }
                .roundIconButton()
                .focused($focused, equals: "hero|info")
            }
            .padding(.top, 8)
        }
        .frame(height: 620 - headerHeight, alignment: .bottomLeading)
        .padding(.horizontal, 80)
        .focusSection()
    }

    private func genreLine(_ item: Item) -> String? {
        var parts: [String] = []
        if !item.isEpisode, let year = item.year { parts.append(String(year)) }
        parts += item.genres.prefix(3)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// An episode's season, number and name ("S1 · E7 · Safe").
    private func detailLine(_ item: Item) -> String? {
        guard item.isEpisode, let s = item.seasonNumber, let e = item.episodeNumber else { return nil }
        return L("card.episode", s, e, item.title)
    }

    /// The focused title's background across the whole screen, darkened at the left and bottom
    /// so the hero's words and the rows read over it.
    private var backdrop: some View {
        let art = hero?.backdrop
        return ArtworkImage(path: art)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(art == nil ? 0 : 1)
            .overlay(LinearGradient(stops: [.init(color: ArcColor.background.opacity(0.85), location: 0), .init(color: .clear, location: 0.65)],
                                    startPoint: .leading, endPoint: .trailing))
            .overlay(LinearGradient(stops: [.init(color: .clear, location: 0.35), .init(color: ArcColor.background.opacity(0.75), location: 0.7),
                                            .init(color: ArcColor.background, location: 1)], startPoint: .top, endPoint: .bottom))
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.5), value: art)
    }

    /// The page Info opens: an episode's show, else the title itself.
    private func pageItem(_ item: Item) -> Item {
        guard item.isEpisode, let show = item.parentId else { return item }
        return Item(id: show, kind: "series", title: item.seriesTitle ?? item.title)
    }

    private func play(_ card: MediaCard) {
        let item = card.item
        if item.playable {
            browse.play(PlayRequest(item: item, startMs: item.resumeMs))
        } else {
            openRoute(.item(item))
        }
    }

    private func toggleWatchlist(_ item: Item) {
        guard let api = app.api else { return }
        let on = item.userData?.watchlisted != true
        Task {
            do {
                try await api.setWatchlisted(item.id, on)
                browse.changed()
            } catch {
                ArcLogApp.warn("Watchlist change failed: \(type(of: error))")
            }
        }
    }

    private var focusedCard: MediaCard? {
        guard let key = focused else { return nil }
        let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return rows.first { $0.id == parts[0] }?.cards.first { $0.id == parts[1] }
    }

    private func open(_ card: MediaCard) {
        let item = card.item
        // Episodes on Continue Watching play at once, as Plex's do; everything else opens its page.
        if item.isEpisode && card.progress != nil {
            browse.play(PlayRequest(item: item, startMs: item.resumeMs))
        } else {
            openRoute(.item(item))
        }
    }
}

extension HeroRows where Header == EmptyView {
    init(rows: [LoadedRow]) {
        self.init(rows: rows) { EmptyView() }
    }
}
