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

/// Home: the focused title's backdrop behind the rows, artwork-led, no banner.
struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var model = HomeModel()
    @State private var path = NavigationPath()
    @State private var playing: PlayRequest?
    @FocusState private var focused: String?

    var body: some View {
        NavigationStack(path: $path) {
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
            .navigationDestination(for: Item.self) { item in
                DetailsView(itemId: item.id, initial: item) { playing = $0 }
            }
        }
        .fullScreenCover(item: $playing, onDismiss: { Task { await reload() } }) { request in
            PlayerScreen(request: request)
        }
        .task { await reload() }
    }

    private var rows: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 48) {
                HStack {
                    if let profile = app.profile {
                        Button { app.switchProfile() } label: {
                            HStack(spacing: 16) {
                                Avatar(profile: profile, size: 56)
                                Text(profile.name).font(.headline)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.horizontal, 80)
                ForEach(model.rows) { row in
                    VStack(alignment: .leading, spacing: 20) {
                        Text(row.title).font(.title3.weight(.semibold)).padding(.horizontal, 80)
                        ScrollView(.horizontal) {
                            LazyHStack(alignment: .top, spacing: 40) {
                                ForEach(row.cards) { card in
                                    MediaCardView(card: card, style: row.spec.style, seasonPosters: row.spec.seasonPosters,
                                                  focus: $focused, focusKey: row.id + "|" + card.id) { open(card) }
                                }
                            }
                            .padding(.horizontal, 80)
                            .padding(.vertical, 24)
                        }
                        .scrollClipDisabled()
                    }
                }
            }
            .padding(.vertical, 40)
        }
    }

    /// The focused title's background, fading into the page.
    private var backdrop: some View {
        let art = focusedCard?.backdrop
        return ArtworkImage(path: art)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(art == nil ? 0 : 0.45)
            .overlay(LinearGradient(colors: [ArcColor.background.opacity(0.2), ArcColor.background], startPoint: .top, endPoint: .bottom))
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.4), value: art)
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
            if retry { Button(L("common.retry")) { Task { await reload() } } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func open(_ card: MediaCard) {
        let item = card.item
        // Episodes on Continue Watching play at once, as Plex's do; everything else opens its page.
        if item.isEpisode && card.progress != nil {
            playing = PlayRequest(item: item, startMs: item.resumeMs)
        } else {
            path.append(item)
        }
    }

    private func reload() async {
        guard let api = app.api else { return }
        await model.load(api) { app.tokenRefused() }
    }
}
