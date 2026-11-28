import ArcKit
import SwiftUI

/// After the profile is chosen: iOS's tab bar (Home, Libraries, Watchlist, Search), which on iPad
/// becomes a sidebar, as Apple's TV app. On iPhone, Libraries opens a menu of the profile's
/// libraries from its button, and the tab shows the one chosen; on iPad the sidebar lists them.
/// The profile button at the top of each tab opens Settings, as the account button in Apple's
/// apps. The player covers the whole screen.
struct MobileTabs: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var browse = Browse()
    @State private var tab = "home"
    @State private var settings = false
    /// A title's page to open on Home (a link from outside the app).
    @State private var homeLink: Route?
    /// The profile's libraries in its order, for the Libraries menu and the iPad's sidebar.
    @State private var libraries: [Library] = []
    @State private var libraryMenu = false
    /// The Libraries tab's page on iPhone: "lib:<id>" or "playlists", kept between launches.
    @AppStorage("mobile.libraries.chosen") private var chosen = ""

    var body: some View {
        TabView(selection: Binding(get: { tab }, set: select)) {
            Tab(L("tab.home"), systemImage: "house", value: "home") {
                MobileStack(link: $homeLink, settings: $settings) { MobileHomeScreen() }
            }
            Tab(L("mobile.tab_libraries"), systemImage: "rectangle.stack", value: "libraries") {
                MobileStack(link: .constant(nil), settings: $settings) {
                    MobileChosenLibrary(libraries: libraries, chosen: sizeClass == .compact ? chosen : "")
                }
                .id(sizeClass == .compact ? chosen : "")
            }
            .defaultVisibility(.hidden, for: .sidebar)
            Tab(L("tab.watchlist"), systemImage: "bookmark", value: "watchlist") {
                MobileStack(link: .constant(nil), settings: $settings) { MobileWatchlistScreen() }
            }
            Tab(L("tab.search"), systemImage: "magnifyingglass", value: "search", role: .search) {
                MobileStack(link: .constant(nil), settings: $settings) { MobileSearchScreen() }
            }
            // The iPad's sidebar: each library, then Playlists, under Libraries.
            TabSection(L("mobile.tab_libraries")) {
                ForEach(libraries) { lib in
                    Tab(lib.name, systemImage: MobileLibrariesScreen.icon(lib), value: "lib:\(lib.id)") {
                        MobileStack(link: .constant(nil), settings: $settings) { MobileLibraryScreen(library: lib) }
                    }
                    .defaultVisibility(.hidden, for: .tabBar)
                }
                Tab(L("tab.playlists"), systemImage: "list.bullet.rectangle", value: "playlists") {
                    MobileStack(link: .constant(nil), settings: $settings) { MobilePlaylistsScreen() }
                }
                .defaultVisibility(.hidden, for: .tabBar)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .environment(browse)
        .overlay(alignment: .bottomLeading) { libraryMenuLayer }
        .sheet(isPresented: $settings) {
            MobileSettingsScreen().environment(browse)
        }
        // Watch Together's invite sheet, from a title's menu. (Inside the player the player shows
        // it itself: one presentation at a time.)
        .sheet(item: Binding(get: { browse.playing == nil ? browse.together.inviting : nil }, set: { browse.together.inviting = $0 })) { target in
            MobileInviteSheet(target: target).environment(browse)
        }
        .sheet(isPresented: Binding(get: { browse.playing == nil && browse.together.enteringCode },
                                    set: { browse.together.enteringCode = $0 })) {
            NavigationStack { MobileJoinCodeScreen { browse.together.enteringCode = false } }
                .environment(browse)
                .presentationDetents([.medium])
        }
        .sheet(item: Binding(get: { browse.playing == nil ? browse.addingToPlaylist : nil }, set: { browse.addingToPlaylist = $0 })) { item in
            MobilePlaylistSheet(item: item)
                .environment(browse)
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: Binding(get: { browse.playing }, set: { browse.playing = $0 })) { request in
            MobilePlayerScreen(request: request).environment(browse)
        }
        .overlay {
            if browse.playing == nil, let notice = browse.together.notice ?? browse.notice { MobileNotice(text: notice) }
        }
        .animation(.easeInOut(duration: 0.25), value: browse.notice)
        .animation(.easeInOut(duration: 0.25), value: browse.together.notice)
        .task {
            // Joining a room, or the room moving to another title, opens the player on it.
            // Settings or the code sheet (where a code is typed) closes first: one presentation
            // at a time.
            browse.together.openPlayer = { item, startMs in
                let request = PlayRequest(item: item, startMs: startMs, together: true)
                guard settings || browse.together.enteringCode else { browse.playing = request; return }
                settings = false
                browse.together.enteringCode = false
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(600))
                    browse.playing = request
                }
            }
        }
        .task(id: app.pendingLink) { await followLink() }
        .task(id: browse.changes) { await loadLibraries() }
        .onChange(of: browse.playing) { _, playing in if playing != nil { libraryMenu = false } }
        // From iPad's sidebar to an iPhone-width window (Split View): a library chosen in the
        // sidebar becomes the Libraries tab's page.
        .onChange(of: sizeClass) { _, size in
            if size == .compact, tab.hasPrefix("lib:") || tab == "playlists" {
                chosen = tab
                tab = "libraries"
            }
        }
        // Arc's live updates while the app is open.
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { app.live.start() } else { app.live.stop() }
        }
        .onDisappear { app.live.stop() }
    }

    /// A tab chosen in the bar. On iPhone, Libraries opens its menu instead (and closes it when
    /// it's open); the tab itself shows once a library is chosen.
    private func select(_ new: String) {
        if new == "libraries" && sizeClass == .compact {
            withAnimation(.spring(duration: 0.3, bounce: 0.15)) { libraryMenu.toggle() }
            return
        }
        if libraryMenu { withAnimation(.easeOut(duration: 0.2)) { libraryMenu = false } }
        tab = new
    }

    private func choose(_ value: String) {
        chosen = value
        tab = "libraries"
        withAnimation(.easeOut(duration: 0.2)) { libraryMenu = false }
    }

    /// The Libraries menu, grown from its button above the tab bar, over a dimmed screen that
    /// closes it when touched.
    @ViewBuilder private var libraryMenuLayer: some View {
        ZStack(alignment: .bottomLeading) {
            if libraryMenu {
                ArcColor.scrim
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { libraryMenu = false } }
                    .accessibilityLabel(Text(L("common.cancel")))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("libraries.menu.close")
                    .transition(.opacity)
                MobileLibraryMenu(libraries: libraries, chosen: tab == "libraries" ? chosen : "", choose: choose)
                    .padding(.leading, 16)
                    .padding(.bottom, 72)
                    .transition(.scale(scale: 0.2, anchor: .bottom).combined(with: .opacity))
            }
        }
    }

    private func loadLibraries() async {
        let (answer, _) = await loadPage(app, "libraries") { api in
            async let prefs = api.prefs()
            async let libs = api.libraries()
            return orderedLibraries(try await libs, order: try await prefs.libraryOrder)
        }
        if let answer { libraries = answer }
    }

    /// arcmediaserver://open/<id> opens the title's page on Home; arcmediaserver://play/<id> plays it.
    private func followLink() async {
        guard let link = app.pendingLink, let api = app.api else { return }
        app.pendingLink = nil
        let id: String
        switch link {
        case .open(let i), .play(let i): id = i
        }
        guard let item = try? await api.item(id) else {
            ArcLogApp.warn("a linked title couldn't be opened")
            return
        }
        switch link {
        case .open:
            browse.playing = nil
            tab = "home"
            homeLink = .item(item)
        case .play:
            browse.play(PlayRequest(item: item, startMs: item.resumeMs))
        }
    }
}

/// The Libraries menu's rows: each library with its icon, a tick on the one showing, then
/// Playlists.
struct MobileLibraryMenu: View {
    let libraries: [Library]
    let chosen: String
    let choose: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if libraries.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            ForEach(Array(libraries.enumerated()), id: \.element.id) { index, lib in
                row(lib.name, icon: MobileLibrariesScreen.icon(lib), value: "lib:\(lib.id)")
                    .accessibilityIdentifier("libraries.menu.\(index)")
            }
            Divider().padding(.vertical, 4).padding(.horizontal, 12)
            row(L("tab.playlists"), icon: "list.bullet.rectangle", value: "playlists")
                .accessibilityIdentifier("libraries.menu.playlists")
        }
        .padding(.vertical, 6)
        .frame(width: 250)
        .arcGlassPanel(cornerRadius: 26)
    }

    private func row(_ name: String, icon: String, value: String) -> some View {
        Button { choose(value) } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 24)
                Text(name).lineLimit(1)
                Spacer(minLength: 8)
                if chosen == value { Image(systemName: "checkmark").font(.footnote.weight(.semibold)) }
            }
            .font(.body)
            .foregroundStyle(ArcColor.foreground)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen == value ? .isSelected : [])
    }
}

/// The Libraries tab's page: on iPhone the library chosen from its menu (or Playlists); otherwise,
/// or before one is chosen, the list of libraries.
struct MobileChosenLibrary: View {
    let libraries: [Library]
    let chosen: String

    var body: some View {
        if chosen == "playlists" {
            MobilePlaylistsScreen()
        } else if let lib = libraries.first(where: { "lib:\($0.id)" == chosen }) {
            MobileLibraryScreen(library: lib)
        } else {
            MobileLibrariesScreen()
        }
    }
}

/// One tab's pages: its first page, then whatever is opened from it, with iOS's back button and
/// swipe. Its first page has the profile button that opens Settings.
struct MobileStack<Root: View>: View {
    @Environment(AppModel.self) private var app
    @Binding var link: Route?
    @Binding var settings: Bool
    @ViewBuilder let root: () -> Root
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            root()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { settings = true } label: {
                            if let profile = app.profile {
                                Avatar(profile: profile, size: 30)
                            } else {
                                Image(systemName: "person.crop.circle")
                            }
                        }
                        .accessibilityLabel(Text(L("tab.settings")))
                        .accessibilityIdentifier("settings.open")
                    }
                }
                .navigationDestination(for: Route.self) { MobileRouteView(route: $0) }
        }
        .environment(\.openRoute, OpenRoute { path.append($0) })
        .onChange(of: link, initial: true) { _, route in
            guard let route else { return }
            link = nil
            path = NavigationPath()
            path.append(route)
        }
    }
}

struct MobileRouteView: View {
    let route: Route

    var body: some View {
        switch route {
        // An episode opens its show's page on that episode, as Plex and Arc's other apps do.
        case .item(let item):
            if let show = item.showOfEpisode {
                MobileDetailsScreen(itemId: show.id, initial: show, episodeId: item.id)
            } else {
                MobileDetailsScreen(itemId: item.id, initial: item)
            }
        case .collection(let id, let title):
            MobileItemsScreen(title: title) { api in try await api.collection(id).items.map { MediaCard(item: $0) } }
        case .playlist(let id, let title):
            MobileItemsScreen(title: title) { api in
                try await api.playlist(id).entries.map { MediaCard(item: $0.item, id: "entry:\($0.entryId)") }
            }
        case .person(let id, let name): MobilePersonScreen(id: id, name: name)
        case .genre(let match): MobileGenreScreen(match: match)
        case .folder(let library, let path, let name): MobileFolderScreen(library: library, path: path, name: name)
        }
    }
}

/// A short note at the top of the screen ("Added “Heat” to the queue"), gone after a moment.
struct MobileNotice: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 18).padding(.vertical, 10)
            .arcGlassPanel(cornerRadius: 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 8)
            .padding(.horizontal, 16)
            .allowsHitTesting(false)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// A page's loading, empty and failed states, the same everywhere.
struct MobileMessage: View {
    let title: String
    var message: String? = nil
    var retry: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Text(title)
        } description: {
            if let message { Text(message) }
        } actions: {
            if let retry { Button(L("common.retry"), action: retry).arcGlassButton() }
        }
    }
}
