import ArcKit
import SwiftUI

/// One row of titles, loaded: on Home, or a library's Recommended.
struct LoadedRow: Identifiable {
    let id: String
    let title: String
    let style: CardStyle
    var seasonPosters = false
    var cards: [MediaCard]
    /// Continue Watching or Up Next: its cards offer Remove from Continue Watching, as the web's do.
    var continueRow = false
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
                return LoadedRow(id: spec.id, title: Self.title(spec.source), style: spec.style, seasonPosters: spec.seasonPosters, cards: cards,
                                 continueRow: Self.isContinue(spec.source))
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
        case .continueWatching(let withUpNext): return try await api.continueWatching(withUpNext: withUpNext).map { MediaCard(item: $0).withShowArt() }
        case .nextUp: return try await api.nextUp().map { MediaCard(item: $0).withShowArt() }
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

    nonisolated private static func isContinue(_ source: RowSource) -> Bool {
        switch source {
        case .continueWatching, .nextUp: return true
        default: return false
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

/// Home: the focused title's hero over the profile's rows (HeroRows).
struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(Browse.self) private var browse
    @State private var model = HomeModel()

    var body: some View {
        Group {
            if model.loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.failed {
                RowsMessage(title: L("home.failed_title"), message: L("common.unreachable")) { Task { await reload() } }
            } else if model.rows.isEmpty {
                RowsMessage(title: L("home.empty_title"), message: L("home.empty_body"), retry: nil)
            } else {
                HeroRows(rows: model.rows, top: browse.together.rooms.isEmpty ? nil : { focus in AnyView(WatchTogetherRow(focus: focus)) })
            }
        }
        // Read again after playing or a change of watch state, so Continue Watching is current.
        .task(id: browse.changes) { await reload() }
        // Watch Together rooms come and go while Home is showing (someone invites this profile):
        // look again every half minute. (Live updates from Arc's events stream are still to come.)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if let api = app.api { await browse.together.refreshRooms(api) }
            }
        }
    }

    private func reload() async {
        guard let api = app.api else { return }
        // The rooms first: a Watch Together row arriving just after the rows took the focus
        // away from the first card (tvOS gave it to the sidebar).
        await browse.together.refreshRooms(api)
        await model.load(api) { app.tokenRefused() }
    }
}

/// What a page of rows says when it has none, or couldn't load them.
struct RowsMessage: View {
    let title: String
    let message: String
    let retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 20) {
            Text(title).font(.title3.weight(.semibold))
            Text(message).foregroundStyle(ArcColor.muted).multilineTextAlignment(.center).frame(maxWidth: 900)
            if let retry { Button(L("common.retry"), action: retry).arcGlassButton() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
