import ArcKit
import SwiftUI

/// A page the app can open from anywhere: a title, a collection, a playlist, a person or a folder.
enum Route: Hashable {
    case item(Item)
    case collection(id: String, title: String)
    case playlist(id: String, title: String)
    case person(id: Int64, name: String)
    case folder(library: Library, path: String, name: String)
}

/// What every page shares: what's playing, and a count bumped when watch state changes (after
/// playing, or Mark as Watched) so pages that show it read it again.
@MainActor
@Observable
final class Browse {
    var playing: PlayRequest?
    private(set) var changes = 0

    func play(_ request: PlayRequest) { playing = request }
    func changed() { changes += 1 }
}

/// Opens a page on the current tab's stack.
struct OpenRoute {
    let action: (Route) -> Void
    func callAsFunction(_ route: Route) { action(route) }
}

private struct OpenRouteKey: EnvironmentKey {
    static let defaultValue = OpenRoute { _ in }
}

extension EnvironmentValues {
    var openRoute: OpenRoute {
        get { self[OpenRouteKey.self] }
        set { self[OpenRouteKey.self] = newValue }
    }
}

/// One tab's pages: its first page, then whatever is opened from it, Back going back up.
struct BrowseStack<Root: View>: View {
    @State private var path = NavigationPath()
    @ViewBuilder let root: () -> Root

    var body: some View {
        NavigationStack(path: $path) {
            root().navigationDestination(for: Route.self) { route in
                RouteView(route: route)
            }
        }
        .environment(\.openRoute, OpenRoute { path.append($0) })
    }
}

struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .item(let item): DetailsView(itemId: item.id, initial: item)
        case .collection(let id, let title): CollectionView(id: id, title: title)
        case .playlist(let id, let title): PlaylistView(id: id, title: title)
        case .person(let id, let name): PersonView(id: id, name: name)
        case .folder(let library, let path, let name): FolderView(library: library, path: path, name: name)
        }
    }
}

/// After the profile is chosen: the tabs along the top (tvOS's own tab bar, as Plex's sidebar
/// sources): Search, Home, the Watchlist and libraries in the profile's order (Arrange
/// libraries on the web), Playlists and Settings. Back from a tab's first page shows the tabs.
struct MainView: View {
    @Environment(AppModel.self) private var app
    @State private var browse = Browse()
    @State private var libraries: [Library] = []
    @State private var watchlistAt = 0
    @State private var tab = "home"

    private enum Tab: Hashable { case watchlist, library(Library) }

    private var middle: [Tab] {
        var out = libraries.map { Tab.library($0) }
        out.insert(.watchlist, at: min(max(watchlistAt, 0), out.count))
        return out
    }

    var body: some View {
        TabView(selection: $tab) {
            BrowseStack { SearchView() }
                .tabItem { Label(L("tab.search"), systemImage: "magnifyingglass") }
                .tag("search")
            BrowseStack { HomeView() }
                .tabItem { Text(L("tab.home")) }
                .tag("home")
            ForEach(middle, id: \.self) { entry in
                switch entry {
                case .watchlist:
                    BrowseStack { WatchlistView() }
                        .tabItem { Text(L("tab.watchlist")) }
                        .tag("watchlist")
                case .library(let library):
                    BrowseStack { LibraryView(library: library) }
                        .tabItem { Text(library.name) }
                        .tag("library:\(library.id)")
                }
            }
            BrowseStack { PlaylistsView() }
                .tabItem { Text(L("tab.playlists")) }
                .tag("playlists")
            BrowseStack { SettingsView() }
                .tabItem { Label(L("tab.settings"), systemImage: "gearshape") }
                .tag("settings")
        }
        .environment(browse)
        .fullScreenCover(item: Binding(get: { browse.playing }, set: { browse.playing = $0 }),
                         onDismiss: { browse.changed() }) { request in
            PlayerScreen(request: request).environment(browse)
        }
        .task { await loadTabs() }
    }

    private func loadTabs() async {
        guard let api = app.api else { return }
        do {
            async let prefsAnswer = api.prefs()
            async let librariesAnswer = api.libraries()
            let (prefs, all) = try await (prefsAnswer, librariesAnswer)
            libraries = orderedLibraries(all, order: prefs.libraryOrder)
            watchlistAt = prefs.watchlistPosition
        } catch let error as APIError where error.status == 401 {
            app.tokenRefused()
        } catch is CancellationError {
        } catch {
            // Home says when Arc can't be reached; the library tabs come back with the next launch.
            ArcLogApp.warn("libraries failed to load: \(type(of: error))")
        }
    }
}
