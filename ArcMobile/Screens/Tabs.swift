import ArcKit
import SwiftUI

/// After the profile is chosen: iOS's tab bar (Home, Libraries, Search), which on iPad becomes a
/// sidebar, as Apple's TV app. The profile button at the top of each tab opens Settings, as the
/// account button in Apple's apps. The player covers the whole screen.
struct MobileTabs: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var browse = Browse()
    @State private var tab = "home"
    @State private var settings = false
    /// A title's page to open on Home (a link from outside the app).
    @State private var homeLink: Route?

    var body: some View {
        TabView(selection: $tab) {
            Tab(L("tab.home"), systemImage: "house", value: "home") {
                MobileStack(link: $homeLink, settings: $settings) { MobileHomeScreen() }
            }
            Tab(L("mobile.tab_libraries"), systemImage: "rectangle.stack", value: "libraries") {
                MobileStack(link: .constant(nil), settings: $settings) { MobileLibrariesScreen() }
            }
            Tab(L("tab.search"), systemImage: "magnifyingglass", value: "search", role: .search) {
                MobileStack(link: .constant(nil), settings: $settings) { MobileSearchScreen() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .environment(browse)
        .sheet(isPresented: $settings) {
            MobileSettingsScreen().environment(browse)
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
            if browse.playing == nil, let notice = browse.notice { MobileNotice(text: notice) }
        }
        .animation(.easeInOut(duration: 0.25), value: browse.notice)
        .task(id: app.pendingLink) { await followLink() }
        // Arc's live updates while the app is open.
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { app.live.start() } else { app.live.stop() }
        }
        .onDisappear { app.live.stop() }
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
