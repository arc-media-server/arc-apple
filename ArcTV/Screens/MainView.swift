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

/// Opens the sidebar (Back from the top of a place's first page, as tvOS apps do).
struct OpenSidebar {
    let action: () -> Void
    func callAsFunction() { action() }
}

private struct OpenSidebarKey: EnvironmentKey {
    static let defaultValue = OpenSidebar {}
}

extension EnvironmentValues {
    var openSidebar: OpenSidebar {
        get { self[OpenSidebarKey.self] }
        set { self[OpenSidebarKey.self] = newValue }
    }
}

/// One place's pages: its first page, then whatever is opened from it, Back going back up. Back on
/// the first page opens the sidebar.
struct BrowseStack<Root: View>: View {
    @Environment(\.openSidebar) private var openSidebar
    @State private var path = NavigationPath()
    @ViewBuilder let root: () -> Root

    var body: some View {
        NavigationStack(path: $path) {
            root()
                .onExitCommand { openSidebar() }
                .navigationDestination(for: Route.self) { route in
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

/// After the profile is chosen: the places, in a sidebar down the left, as Plozz and Apple's own
/// apps have one (owner, 1 November: Plozz's). Its icons always show, in the same places; moving
/// left onto them opens it, its glass and the names fading in around them, and Select opens the
/// place. The places: Search, Home, the Watchlist and libraries in the profile's order (Arrange
/// libraries on the web), Playlists and Settings. Back from a place's first page opens the sidebar.
struct MainView: View {
    @Environment(AppModel.self) private var app
    @State private var browse = Browse()
    @State private var libraries: [Library] = []
    @State private var watchlistAt = 0
    @State private var tab = "home"
    /// The places opened so far: each keeps its pages while another is showing.
    @State private var opened: Set<String> = ["home"]
    @FocusState private var focused: String?
    /// While true, an invisible stop at the top left of the page can take the focus: choosing a
    /// place moves the focus there, out of the sidebar, and the next press goes on into the page.
    @State private var landingArmed = false

    /// A place in the sidebar.
    private struct Place: Hashable, Identifiable {
        let id: String
        let title: String
        let icon: String
        var library: Library? = nil
    }

    private var places: [Place] {
        var middle = libraries.map { lib in
            Place(id: "library:\(lib.id)", title: lib.name,
                  icon: lib.kind == "shows" ? "tv" : lib.kind == "videos" ? "video" : "film", library: lib)
        }
        middle.insert(Place(id: "watchlist", title: L("tab.watchlist"), icon: "bookmark"), at: min(max(watchlistAt, 0), middle.count))
        return [Place(id: "search", title: L("tab.search"), icon: "magnifyingglass"),
                Place(id: "home", title: L("tab.home"), icon: "house")]
            + middle
            + [Place(id: "playlists", title: L("tab.playlists"), icon: "list.bullet.rectangle"),
               Place(id: "settings", title: L("tab.settings"), icon: "gearshape")]
    }

    private var sidebarOpen: Bool { focused != nil && focused != Sidebar.landing }

    var body: some View {
        ZStack(alignment: .leading) {
            ZStack {
                ForEach(places.filter { opened.contains($0.id) }) { place in
                    let showing = place.id == tab
                    page(for: place)
                        .opacity(showing ? 1 : 0)
                        .disabled(!showing)
                        .accessibilityHidden(!showing)
                }
            }
            .safeAreaPadding(.leading, Sidebar.collapsedWidth - 20)
            .environment(\.openSidebar, OpenSidebar { focused = tab })

            Color.clear
                .frame(width: 4, height: 4)
                .focusable(landingArmed)
                .focused($focused, equals: Sidebar.landing)
                .onExitCommand { focused = tab }
                .accessibilityHidden(true)
                .padding(.leading, Sidebar.collapsedWidth + 90)
                .padding(.top, 60)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // The page dims behind the open sidebar, so its names read over any artwork.
            LinearGradient(colors: [.black.opacity(0.75), .black.opacity(0)], startPoint: .leading, endPoint: .trailing)
                .frame(width: 900)
                .ignoresSafeArea()
                .opacity(sidebarOpen ? 1 : 0)
                .allowsHitTesting(false)

            sidebar
        }
        .animation(.easeOut(duration: 0.25), value: sidebarOpen)
        .onChange(of: focused) { old, new in
            // Leaving the stop on the page: it can't be reached again until the next choice.
            if old == Sidebar.landing { landingArmed = false }
            // Coming into the sidebar from a page starts on the place showing, wherever the focus
            // came from. (A step later: tvOS ignores a focus change made while it's moving it.)
            if old == nil || old == Sidebar.landing {
                if let new, new != tab, new != Sidebar.landing { Task { @MainActor in focused = tab } }
            } else if new == Sidebar.above {
                // Past the first or last place the focus stays in the sidebar, rather than
                // jumping to whatever on the page lies that way.
                Task { @MainActor in focused = app.profile == nil ? places.first?.id : Sidebar.profile }
            } else if new == Sidebar.below {
                Task { @MainActor in focused = places.last?.id }
            }
        }
        .environment(browse)
        .fullScreenCover(item: Binding(get: { browse.playing }, set: { browse.playing = $0 }),
                         onDismiss: { browse.changed() }) { request in
            PlayerScreen(request: request).environment(browse)
        }
        .task { await loadTabs() }
    }

    @ViewBuilder private func page(for place: Place) -> some View {
        switch place.id {
        case "search": BrowseStack { SearchView() }
        case "home": BrowseStack { HomeView() }
        case "watchlist": BrowseStack { WatchlistView() }
        case "playlists": BrowseStack { PlaylistsView() }
        case "settings": BrowseStack { SettingsView() }
        default:
            if let library = place.library { BrowseStack { LibraryView(library: library) } }
        }
    }

    /// Shut, only the icons show, straight on the page, with a grey disc behind the place showing;
    /// open, a tall glass panel comes in behind them with the names, the profile's name at the
    /// top (Select switches profile), and the focused place in white.
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            edge(Sidebar.above)
            if let profile = app.profile {
                Button { app.switchProfile() } label: {
                    Sidebar.Row(icon: nil, profile: profile, title: profile.name, current: false, open: sidebarOpen)
                }
                .buttonStyle(Sidebar.RowStyle())
                .focused($focused, equals: Sidebar.profile)
                .padding(.bottom, 12)
            }
            ForEach(places) { place in
                Button {
                    tab = place.id
                    opened.insert(place.id)
                    handOver()
                } label: {
                    Sidebar.Row(icon: place.icon, title: place.title, current: place.id == tab, open: sidebarOpen)
                }
                .buttonStyle(Sidebar.RowStyle())
                .focused($focused, equals: place.id)
            }
            edge(Sidebar.below)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Sidebar.inset)
        .padding(.vertical, 40)
        .frame(width: sidebarOpen ? Sidebar.openWidth : Sidebar.collapsedWidth, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(alignment: .leading) {
            Color.clear
                .frame(width: Sidebar.openWidth)
                .frame(maxHeight: .infinity)
                .arcGlassPanel(cornerRadius: 48)
                .opacity(sidebarOpen ? 1 : 0)
        }
        .focusSection()
        .padding(.vertical, 30)
        .padding(.leading, 30)
        .ignoresSafeArea()
    }

    /// Moves the focus from the sidebar onto the page: to the stop at the page's top left (tvOS
    /// can't be told to focus "something on the page", only a view it knows), so the sidebar shuts
    /// and the next press moves on into the page from there.
    private func handOver() {
        landingArmed = true
        Task { @MainActor in focused = Sidebar.landing }
    }

    /// An invisible stop above and below the places (see onChange above).
    private func edge(_ id: String) -> some View {
        Color.clear.frame(height: 1)
            .focusable()
            .focused($focused, equals: id)
            .accessibilityHidden(true)
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

/// The sidebar's measures and rows: an icon at a fixed place, its name fading in beside it when
/// the sidebar opens; the focused row white with black, as Apple's sidebar.
enum Sidebar {
    static let inset: CGFloat = 12
    static let icon: CGFloat = 72
    static let collapsedWidth: CGFloat = icon + inset * 2
    static let openWidth: CGFloat = 440
    static let profile = "sidebar:profile"
    static let landing = "sidebar:landing"
    static let above = "sidebar:above"
    static let below = "sidebar:below"

    struct Row: View {
        let icon: String?
        var profile: Profile? = nil
        let title: String
        let current: Bool
        let open: Bool
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            HStack(spacing: 16) {
                ZStack {
                    // The place showing, while the sidebar is shut: a grey disc behind its icon.
                    Circle().fill(.white.opacity(0.22)).opacity(current && !open ? 1 : 0)
                    if let profile {
                        Avatar(profile: profile, size: 46)
                    } else if let icon {
                        Image(systemName: icon).font(.system(size: 28, weight: .semibold))
                    }
                }
                .frame(width: Sidebar.icon, height: Sidebar.icon)
                Text(title)
                    .font(.system(size: 30, weight: current || profile != nil ? .semibold : .medium))
                    .lineLimit(1)
                    .opacity(open ? 1 : 0)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isFocused ? Color.black : current || !open ? Color.white : Color.white.opacity(0.85))
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                Capsule().fill(.white).opacity(isFocused ? 1 : 0)
            }
            .shadow(color: .black.opacity(open ? 0 : 0.5), radius: 6) // icons over bright artwork
            .contentShape(Capsule())
        }
    }

    /// No lift or system highlight: the row draws its own.
    struct RowStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
        }
    }
}
