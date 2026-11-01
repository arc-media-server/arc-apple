import ArcKit
import SwiftUI

/// One row on Home, loaded.
struct LoadedRow: Identifiable {
    let spec: HomeRowSpec
    let title: String
    var cards: [MediaCard]
    var id: String { spec.id }
}

/// Home's rows for the profile, arranged as on the web (Edit Home, Arrange libraries): the
/// Apple TV follows that layout rather than having its own.
@MainActor
@Observable
final class HomeModel {
    private(set) var rows: [LoadedRow] = []
    private(set) var loading = true
    private(set) var failed = false

    func load(_ api: ArcAPI, onRefused: () -> Void) async {
        loading = rows.isEmpty
        failed = false
        let started = Date()
        do {
            async let prefsAnswer = api.prefs()
            async let librariesAnswer = api.libraries()
            let (prefs, libraries) = try await (prefsAnswer, librariesAnswer)
            let specs = resolveHomeRows(prefs: prefs, libraries: orderedLibraries(libraries, order: prefs.libraryOrder))
            var loaded: [String: [MediaCard]] = [:]
            var problems = 0
            await withTaskGroup(of: (String, [MediaCard]?).self) { group in
                for spec in specs {
                    group.addTask { (spec.id, try? await Self.cards(spec.source, api)) }
                }
                for await (id, cards) in group {
                    if let cards { loaded[id] = cards } else { problems += 1 }
                }
            }
            rows = specs.compactMap { spec in
                guard let cards = loaded[spec.id], !cards.isEmpty else { return nil }
                return LoadedRow(spec: spec, title: Self.title(spec.source), cards: cards)
            }
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            if problems > 0 { ArcLogApp.warn("Home: \(problems) of \(specs.count) rows failed to load") }
            ArcLogApp.debug("Home loaded \(rows.count) rows in \(ms) ms")
        } catch let error as APIError where error.status == 401 {
            onRefused()
        } catch is CancellationError {
        } catch {
            ArcLogApp.warn("Home failed to load: \(type(of: error))")
            failed = rows.isEmpty
        }
        loading = false
    }

    nonisolated private static func cards(_ source: RowSource, _ api: ArcAPI) async throws -> [MediaCard] {
        switch source {
        case .continueWatching(let withUpNext): return try await api.continueWatching(withUpNext: withUpNext).map { MediaCard(item: $0) }
        case .nextUp: return try await api.nextUp().map { MediaCard(item: $0) }
        case .watchlist: return try await api.watchlist().map { MediaCard(item: $0) }
        case .recent(let lib, let showsOnly):
            if lib.kind == "shows" && !showsOnly { return try await api.recentShows(libraryId: lib.id).map { MediaCard(recent: $0) } }
            return try await api.items(libraryQuery(lib, sort: "added", limit: 24)).items.map { MediaCard(item: $0) }
        case .custom(_, let lib, let filter): return try await api.items(customRowQuery(filter: filter, library: lib)).items.map { MediaCard(item: $0) }
        case .seasonal(let pick): return try await api.items(pick.query.merging(["limit": "24"]) { a, _ in a }).items.map { MediaCard(item: $0) }
        case .collection(let id, _): return try await api.collection(id).items.map { MediaCard(item: $0) }
        case .playlist(let id, _): return try await api.playlist(id).entries.map { MediaCard(item: $0.item, id: "entry:\($0.entryId)") }
        }
    }

    nonisolated private static func title(_ source: RowSource) -> String {
        switch source {
        case .continueWatching: return L("row.continue")
        case .nextUp: return L("row.next_up")
        case .watchlist: return L("row.watchlist")
        case .recent(let lib, _): return L("row.recent", lib.name)
        case .custom(let title, _, _): return title
        case .seasonal(.romance): return L("row.seasonal_romance")
        case .seasonal(.horror): return L("row.seasonal_horror")
        case .seasonal(.christmas): return L("row.seasonal_christmas")
        case .collection(_, let title): return title.isEmpty ? L("row.collection") : title
        case .playlist(_, let title): return title.isEmpty ? L("row.playlist") : title
        }
    }
}

/// Home: a full-screen hero for the focused title (its background, logo or name, details and
/// glass Play, Watchlist and Info buttons) with the rows beneath, the first one peeking up.
struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(Browse.self) private var browse
    @Environment(\.openRoute) private var openRoute
    @State private var model = HomeModel()
    /// The title the hero shows: the focused card, or the one last focused.
    @State private var hero: MediaCard?
    @FocusState private var focused: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            backdrop
            if model.loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.failed {
                message(L("home.failed_title"), L("common.unreachable"), retry: true)
            } else if model.rows.isEmpty {
                message(L("home.empty_title"), L("home.empty_body"), retry: false)
            } else {
                rows
            }
        }
        // Read again after playing or a change of watch state, so Continue Watching is current.
        .task(id: browse.changes) { await reload() }
        // Focus starts on the first title, as Plex's Home.
        .onChange(of: model.loading) { _, now in
            if !now, focused == nil, let row = model.rows.first, let card = row.cards.first {
                hero = card
                Task { @MainActor in focused = row.id + "|" + card.id }
            }
        }
        .onChange(of: focused) { _, _ in
            if let card = focusedCard { hero = card }
        }
    }

    private var rows: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 44) {
                if let hero { heroDetails(hero) }
                ForEach(model.rows) { row in
                    VStack(alignment: .leading, spacing: 16) {
                        Text(row.title).font(.headline).padding(.horizontal, 80)
                        ScrollView(.horizontal) {
                            LazyHStack(alignment: .top, spacing: 36) {
                                ForEach(row.cards) { card in
                                    MediaCardView(card: card, style: row.spec.style, seasonPosters: row.spec.seasonPosters,
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
            .padding(.bottom, 60)
        }
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
            Text(heroMeta(item)).font(.callout.weight(.medium)).foregroundStyle(.white.opacity(0.85))
            if let overview = item.overview, !overview.isEmpty {
                Text(overview).font(.callout).foregroundStyle(.white.opacity(0.75)).lineLimit(3).frame(maxWidth: 760, alignment: .leading)
            }
            HStack(spacing: 20) {
                Button { play(card) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "play.fill")
                        if let progress = card.progress, let left = card.minutesLeft {
                            ProgressBar(fraction: progress).frame(width: 90)
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
        .frame(height: 620, alignment: .bottomLeading)
        .padding(.horizontal, 80)
        .focusSection()
    }

    private func heroMeta(_ item: Item) -> String {
        var parts: [String] = []
        if item.isEpisode, let s = item.seasonNumber, let e = item.episodeNumber { parts.append(L("card.episode", s, e, item.title)) }
        if let year = item.year { parts.append(String(year)) }
        if let rating = item.contentRating, !rating.isEmpty { parts.append(rating) }
        parts += item.genres.prefix(3)
        return parts.joined(separator: " · ")
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
        return model.rows.first { $0.id == parts[0] }?.cards.first { $0.id == parts[1] }
    }

    private func message(_ title: String, _ body: String, retry: Bool) -> some View {
        VStack(spacing: 20) {
            Text(title).font(.title3.weight(.semibold))
            Text(body).foregroundStyle(ArcColor.muted).multilineTextAlignment(.center).frame(maxWidth: 900)
            if retry { Button(L("common.retry")) { Task { await reload() } }.arcGlassButton() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func reload() async {
        guard let api = app.api else { return }
        await model.load(api) { app.tokenRefused() }
    }
}
