import ArcKit
import SwiftUI

/// Libraries: the profile's libraries in its order (Arrange libraries on the web), then the
/// Watchlist and Playlists, as an iOS list, the way the Apple TV's sidebar lists them.
struct MobileLibrariesScreen: View {
    @Environment(AppModel.self) private var app
    @State private var libraries: [Library] = []
    @State private var loading = true
    @State private var problem: String?

    var body: some View {
        List {
            if !libraries.isEmpty {
                Section {
                    ForEach(libraries) { lib in
                        NavigationLink {
                            MobileLibraryScreen(library: lib)
                        } label: {
                            Label(lib.name, systemImage: Self.icon(lib))
                        }
                    }
                }
            }
            Section {
                NavigationLink {
                    MobileItemsScreen(title: L("tab.watchlist"), empty: L("mobile.watchlist_empty")) { api in
                        try await api.watchlist().map { MediaCard(item: $0) }
                    }
                } label: {
                    Label(L("tab.watchlist"), systemImage: "bookmark")
                }
                NavigationLink {
                    MobilePlaylistsScreen()
                } label: {
                    Label(L("tab.playlists"), systemImage: "list.bullet.rectangle")
                }
            }
        }
        .overlay {
            if loading && libraries.isEmpty {
                ProgressView()
            } else if let problem, libraries.isEmpty {
                MobileMessage(title: problem) { Task { await load() } }
            }
        }
        .navigationTitle(L("mobile.tab_libraries"))
        .refreshable { await load() }
        .task { await load() }
    }

    static func icon(_ lib: Library) -> String {
        lib.kind == "shows" ? "tv" : lib.kind == "videos" ? "video" : "film"
    }

    private func load() async {
        let (answer, failed) = await loadPage(app, "libraries") { api in
            async let prefs = api.prefs()
            async let libs = api.libraries()
            return orderedLibraries(try await libs, order: try await prefs.libraryOrder)
        }
        if let answer { libraries = answer }
        problem = failed
        loading = false
    }
}

/// A library: its titles in a grid, sorted and filtered from the toolbar (Sort, Unwatched Only),
/// or its collections; an Other videos library shows its folders.
struct MobileLibraryScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Browse.self) private var browse
    let library: Library
    /// A genre's titles (a genre from search): the grid starts filtered to it.
    var genre: String? = nil
    var title: String? = nil

    enum Show: Hashable { case titles, collections }
    @State private var show: Show = .titles
    @State private var query = LibraryQuery()
    @State private var items: [Item] = []
    @State private var total = 0
    @State private var collections: [CollectionSummary] = []
    @State private var loading = true
    @State private var loadingMore = false
    @State private var problem: String?
    private static let page = 60

    var body: some View {
        Group {
            if library.kind == "videos" {
                MobileFolderScreen(library: library, path: "", name: library.name, isRoot: true)
            } else {
                ScrollView {
                    if genre == nil {
                        Picker("", selection: $show) {
                            Text(L("library.titles")).tag(Show.titles)
                            Text(L("library.collections")).tag(Show.collections)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    }
                    content
                }
                .refreshable { await reload() }
                .toolbar {
                    if show == .titles { ToolbarItem(placement: .topBarTrailing) { sortMenu } }
                }
                .task(id: [String(describing: show), String(describing: query)]) { await reload() }
                .task(id: browse.changes) { if !loading { await reload() } }
            }
        }
        .navigationTitle(title ?? library.name)
        .navigationBarTitleDisplayMode(.inline)
        .background(PageWash())
        .onAppear { if let genre, query.genre == nil { query.genre = genre } }
    }

    @ViewBuilder private var content: some View {
        if loading {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
        } else if let problem {
            MobileMessage(title: problem) { Task { await reload() } }
        } else {
            switch show {
            case .titles:
                if items.isEmpty {
                    MobileMessage(title: query.filtered ? L("library.nothing_matches") : L("library.empty"))
                } else {
                    Text(query.filtered ? L("library.count_filtered", total) : L("library.count", total))
                        .font(.footnote).foregroundStyle(ArcColor.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.bottom, 8)
                    MobileGrid(cards: items.map { MediaCard(item: $0) }) { Task { await more() } }
                    if loadingMore { ProgressView().padding() }
                }
            case .collections:
                if collections.isEmpty {
                    MobileMessage(title: L("library.no_collections"))
                } else {
                    MobileCollectionGrid(collections: collections)
                }
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker(L("mobile.sort"), selection: $query.sort) {
                ForEach(LibrarySort.allCases, id: \.self) { Text(Self.sortName($0)).tag($0) }
            }
            Toggle(isOn: $query.reversed) { Label(L("mobile.sort_reversed"), systemImage: "arrow.up.arrow.down") }
            Toggle(isOn: Binding(get: { query.unwatchedOnly }, set: { query.setUnwatched($0) })) {
                Label(L("library.unwatched"), systemImage: "eye.slash")
            }
            if query.filtered && genre == nil {
                Button(L("library.clear_filters"), role: .destructive) { query = query.cleared }
            }
        } label: {
            Label(L("mobile.sort"), systemImage: query.filtered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityIdentifier("library.sort")
    }

    static func sortName(_ sort: LibrarySort) -> String {
        switch sort {
        case .title: return L("library.sort_title")
        case .added: return L("library.sort_added")
        case .released: return L("library.sort_released")
        case .year: return L("library.sort_year")
        case .rating: return L("library.sort_rating")
        case .runtime: return L("library.sort_runtime")
        case .lastPlayed: return L("library.sort_watched")
        }
    }

    private func reload() async {
        if let genre, query.genre == nil { query.genre = genre; return }
        problem = nil
        let started = Date()
        switch show {
        case .titles:
            let params = query.parameters(library: library, offset: 0, limit: Self.page)
            let (page, failed) = await loadPage(app, "library") { try await $0.items(params) }
            if let page {
                items = page.items
                total = page.total
                ArcLogApp.debug("library \(library.id): \(page.items.count) of \(page.total) titles in \(Int(Date().timeIntervalSince(started) * 1000)) ms")
            }
            problem = failed
        case .collections:
            let (answer, failed) = await loadPage(app, "library collections") { try await $0.collections(libraryId: library.id) }
            if let answer { collections = answer }
            problem = failed
        }
        loading = false
    }

    private func more() async {
        guard show == .titles, !loadingMore, items.count < total else { return }
        loadingMore = true
        defer { loadingMore = false }
        let params = query.parameters(library: library, offset: items.count, limit: Self.page)
        let (page, _) = await loadPage(app, "library page") { try await $0.items(params) }
        if let page { items += page.items.filter { new in !items.contains { $0.id == new.id } } }
    }
}

/// Collections as posters with their name and count.
struct MobileCollectionGrid: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.openRoute) private var openRoute
    let collections: [CollectionSummary]

    var body: some View {
        let wide = sizeClass == .regular
        LazyVGrid(columns: [GridItem(.adaptive(minimum: Metrics.gridPoster(wide)), spacing: 12, alignment: .top)], spacing: 20) {
            ForEach(collections) { c in
                Button { openRoute(.collection(id: c.id, title: c.title)) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Color.clear.aspectRatio(2.0 / 3.0, contentMode: .fit)
                            .overlay { ArtworkImage(path: c.images?.primary) }
                            .clipShape(RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous))
                        Text(c.title).font(.footnote.weight(.semibold)).lineLimit(1)
                        Text(L("library.count", c.count)).font(.caption).foregroundStyle(ArcColor.muted)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Metrics.margin(wide))
    }
}

/// A list of titles loaded in one go: the Watchlist, a collection, a playlist.
struct MobileItemsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Browse.self) private var browse
    let title: String
    var empty: String? = nil
    let load: (ArcAPI) async throws -> [MediaCard]
    @State private var cards: [MediaCard]?
    @State private var problem: String?

    var body: some View {
        ScrollView {
            if let cards {
                if cards.isEmpty {
                    MobileMessage(title: empty ?? L("browse.folder_empty"))
                } else {
                    MobileGrid(cards: cards).padding(.vertical, 8)
                }
            } else if let problem {
                MobileMessage(title: problem) { Task { await reload() } }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .background(PageWash())
        .refreshable { await reload() }
        .task(id: browse.changes) { await reload() }
    }

    private func reload() async {
        let (answer, failed) = await loadPage(app, "titles") { try await load($0) }
        if let answer { cards = answer }
        problem = failed
    }
}

/// The profile's playlists (made on the web), each opening its titles.
struct MobilePlaylistsScreen: View {
    @Environment(AppModel.self) private var app
    @State private var playlists: [PlaylistSummary]?
    @State private var problem: String?

    var body: some View {
        List {
            ForEach(playlists ?? []) { list in
                NavigationLink(value: Route.playlist(id: list.id, title: list.title)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(list.title)
                        Text(L("playlist_add.count", list.count)).font(.caption).foregroundStyle(ArcColor.muted)
                    }
                }
            }
        }
        .overlay {
            if playlists == nil && problem == nil {
                ProgressView()
            } else if let problem {
                MobileMessage(title: problem) { Task { await reload() } }
            } else if playlists?.isEmpty == true {
                MobileMessage(title: L("browse.playlists_empty"))
            }
        }
        .navigationTitle(L("tab.playlists"))
        .task { await reload() }
    }

    private func reload() async {
        let (answer, failed) = await loadPage(app, "playlists") { try await $0.playlists() }
        if let answer { playlists = answer }
        problem = failed
    }
}

/// A genre from search: its library's titles in that genre.
struct MobileGenreScreen: View {
    @Environment(AppModel.self) private var app
    let match: GenreMatch
    @State private var library: Library?
    @State private var missing = false

    var body: some View {
        Group {
            if let library {
                MobileLibraryScreen(library: library, genre: match.name, title: match.name)
            } else if missing {
                MobileMessage(title: L("search.genre_unavailable"))
            } else {
                ProgressView()
            }
        }
        .task {
            let (libs, _) = await loadPage(app, "libraries") { try await $0.libraries() }
            library = libs?.first { $0.id == match.libraryId }
            missing = library == nil
        }
    }
}

/// An Other videos library's folder: its folders, then its videos.
struct MobileFolderScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openRoute) private var openRoute
    let library: Library
    let path: String
    let name: String
    var isRoot = false
    @State private var page: FolderPage?
    @State private var problem: String?

    var body: some View {
        List {
            if let page {
                ForEach(page.folders) { folder in
                    Button { openRoute(.folder(library: library, path: folder.path, name: folder.name)) } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(folder.name).foregroundStyle(ArcColor.foreground)
                                Text(L("library.count", folder.count)).font(.caption).foregroundStyle(ArcColor.muted)
                            }
                        } icon: {
                            Image(systemName: "folder")
                        }
                    }
                }
                ForEach(page.items) { item in
                    Button { openRoute(.item(item)) } label: {
                        Label(item.title, systemImage: "film").foregroundStyle(ArcColor.foreground)
                    }
                }
            }
        }
        .overlay {
            if page == nil && problem == nil {
                ProgressView()
            } else if let problem {
                MobileMessage(title: problem) { Task { await reload() } }
            } else if let page, page.folders.isEmpty && page.items.isEmpty {
                MobileMessage(title: L("browse.folder_empty"))
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(isRoot ? .inline : .automatic)
        .task { await reload() }
    }

    private func reload() async {
        let (answer, failed) = await loadPage(app, "folder") { try await $0.folders(libraryId: library.id, path: path) }
        if let answer { page = answer }
        problem = failed
    }
}

/// A person: their picture and name, then what they're in.
struct MobilePersonScreen: View {
    @Environment(AppModel.self) private var app
    let id: Int64
    let name: String
    @State private var page: PersonPage?
    @State private var problem: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ArtworkImage(path: page?.person.image)
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
                if let known = page?.person.knownFor, !known.isEmpty {
                    Text(known).font(.subheadline).foregroundStyle(ArcColor.muted)
                }
            }
            .padding(.vertical, 16)
            if let page {
                MobileGrid(cards: page.credits.map { MediaCard(item: $0.item) })
            } else if let problem {
                MobileMessage(title: problem) { Task { await reload() } }
            } else {
                ProgressView().padding(.top, 40)
            }
        }
        .navigationTitle(name)
        .background(PageWash())
        .task { await reload() }
    }

    private func reload() async {
        let (answer, failed) = await loadPage(app, "person") { try await $0.person(id) }
        if let answer { page = answer }
        problem = failed
    }
}
