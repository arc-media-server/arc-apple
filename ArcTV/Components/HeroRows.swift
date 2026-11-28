import ArcKit
import SwiftUI

/// Focusable rows of titles. Home shows the focused title above the rows, and
/// a library's Recommended page starts at its rows beneath the library tabs.
struct HeroRows<Header: View>: View {
    @Environment(AppModel.self) private var app
    @Environment(Browse.self) private var browse
    @Environment(\.openRoute) private var openRoute
    let rows: [LoadedRow]
    var showsHero = true
    /// A row of its own among the titles' rows (Home's Watch Together row), under Continue
    /// Watching, or under the first row when there's none. The first titles' row keeps the top and
    /// the focus, so the hero describes them (owner, 27 November). It gets the page's focus binding;
    /// its cards' focus keys start with "top|".
    var top: ((FocusState<String?>.Binding) -> AnyView)? = nil
    @ViewBuilder var header: () -> Header
    /// The title the hero shows: the focused card, or the one last focused.
    @State private var hero: MediaCard?
    @FocusState private var focused: String?
    /// The row the focus is in, so the page moves only when the focus changes rows.
    @State private var focusedRow: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if showsHero { backdrop }
            ScrollViewReader { proxy in
            ScrollView(.vertical) {
                // The gap between rows is each row's foot (below), which is what lines up with the
                // bottom of the screen.
                LazyVStack(alignment: .leading, spacing: 44 - Self.foot) {
                    if showsHero {
                        if let hero { heroDetails(hero) }
                    } else {
                        // The rows have their own bottom spacer. Give the tabs the same
                        // separation as Browse, where a focused card can grow beneath them.
                        header().padding(.bottom, Self.foot)
                    }
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(row.title).font(.title3.weight(.semibold)).padding(.horizontal, 80)
                            ScrollView(.horizontal) {
                                LazyHStack(alignment: .top, spacing: 36) {
                                    ForEach(row.cards) { card in
                                        MediaCardView(card: card, style: row.style, seasonPosters: row.seasonPosters,
                                                      continueRow: row.continueRow, queueEntry: row.queueRow ? card.id : nil, showsLength: false, focus: $focused, focusKey: row.id + "|" + card.id) { open(card, in: row) }
                                    }
                                }
                                .padding(.horizontal, 80)
                                .padding(.vertical, 20)
                            }
                            .scrollClipDisabled()
                        }
                            Color.clear.frame(height: Self.foot).id(row.id)
                        }
                        if let top, row.id == topAfter {
                            // Its foot, as the rows' above, is where it lands.
                            VStack(alignment: .leading, spacing: 0) {
                                top($focused)
                                Color.clear.frame(height: Self.foot).id("top")
                            }
                        }
                    }
                }
                .padding(.bottom, 60)
            }
            // The row the focus moves into lands at the foot of the screen, moving down or back
            // up, with the rows above it in view, the hero above the first (as Android's and Kodi's
            // rows, and Plex's). tvOS would otherwise scroll only as far as needed, which
            // going up leaves the row at the top.
            .onChange(of: focused) { old, key in
                guard let key else { return }
                let row = String(key.split(separator: "|", maxSplits: 1).first ?? "")
                guard row != focusedRow else { return }
                focusedRow = row
                // Every row lands at the foot, the first too: under the hero, with its names in
                // full (owner, 27 November). On opening, a moment later as well, once the rows
                // have been laid out.
                withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(row, anchor: .bottom) }
                if old == nil {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(150))
                        proxy.scrollTo(row, anchor: .bottom)
                    }
                }
            }
            }
        }
        // Focus starts on the first title, as Plex's Home and library pages.
        .onAppear { focusFirst() }
        .onChange(of: rows.first?.cards.first?.id) { _, _ in focusFirst() }
        .onChange(of: focused) { _, _ in
            if showsHero, let card = focusedCard { hero = card }
        }
    }

    /// What stays under the focused row at the foot of the screen.
    static var foot: CGFloat { 36 }

    /// The row the `top` row sits under: Continue Watching, or else the first row.
    private var topAfter: String? { (rows.first(where: \.continueRow) ?? rows.first)?.id }

    private func focusFirst() {
        guard focused == nil, let row = rows.first, let card = row.cards.first else { return }
        if showsHero && hero == nil { hero = card }
        let key = row.id + "|" + card.id
        Task { @MainActor in focused = key }
    }

    /// The hero's words over the background; the first row starts just under it.
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
            // The hero line: the rating in a box, then the genres; an episode's own line under it.
            HStack(spacing: 12) {
                if let rating = item.contentRating, !rating.isEmpty { OutlinedBadge(text: rating) }
                if let line = genreLine(item) { Text(line) }
            }
            .font(.callout.weight(.medium)).foregroundStyle(.white.opacity(0.85))
            if let line = detailLine(item) {
                Text(line).font(.callout).foregroundStyle(.white.opacity(0.85))
            }
            if let overview = item.overview(hidingSpoilers: app.hideSpoilers) {
                Text(overview).font(.callout).foregroundStyle(.white.opacity(0.75)).lineLimit(3).frame(maxWidth: 760, alignment: .leading)
            }
        }
        .frame(height: 620, alignment: .bottomLeading)
        .padding(.horizontal, 80)
    }

    private func genreLine(_ item: Item) -> String? {
        var parts: [String] = []
        if !item.isEpisode, let yearAndEdition = item.yearAndEdition { parts.append(yearAndEdition) }
        parts += item.genres.prefix(3)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// An episode's season, number and name ("S1 · E7 · Safe").
    private func detailLine(_ item: Item) -> String? {
        guard item.isEpisode else { return nil }
        // Outside the show's order there's no "S0 · E0": just the episode's name.
        return item.episodeLine
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

    private var focusedCard: MediaCard? {
        guard let key = focused else { return nil }
        let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return rows.first { $0.id == parts[0] }?.cards.first { $0.id == parts[1] }
    }

    private func open(_ card: MediaCard, in row: LoadedRow) {
        let item = card.item
        // The Queue row plays on from that entry.
        if row.queueRow {
            browse.play(PlayRequest(item: item, startMs: item.resumeMs, queueEntry: card.id))
            return
        }
        // Episodes on Continue Watching play at once, as Plex's do; everything else opens its page.
        if item.isEpisode && card.progress != nil {
            browse.play(PlayRequest(item: item, startMs: item.resumeMs))
        } else {
            openRoute(.item(item))
        }
    }
}

extension HeroRows where Header == EmptyView {
    init(rows: [LoadedRow], top: ((FocusState<String?>.Binding) -> AnyView)? = nil) {
        self.init(rows: rows, top: top) { EmptyView() }
    }
}
