import ArcKit
import SwiftUI

/// A collection's titles.
struct CollectionView: View {
    @Environment(AppModel.self) private var app
    @Environment(Browse.self) private var browse
    let id: String
    let title: String
    @State private var items: [Item] = []
    @State private var loading = true
    @State private var problem: String?

    var body: some View {
        PageScaffold(title: title, loading: loading, problem: problem, empty: items.isEmpty ? L("browse.collection_empty") : nil) {
            TitleGrid(items: items)
        }
        .task(id: browse.changes) {
            let (page, failed) = await loadPage(app, "collection") { try await $0.collection(id) }
            if let page { items = page.items }
            problem = failed
            loading = false
        }
    }
}

/// A playlist's titles, in its order.
struct PlaylistView: View {
    @Environment(AppModel.self) private var app
    @Environment(Browse.self) private var browse
    let id: String
    let title: String
    @State private var items: [Item] = []
    @State private var loading = true
    @State private var problem: String?

    var body: some View {
        PageScaffold(title: title, loading: loading, problem: problem, empty: items.isEmpty ? L("browse.playlist_empty") : nil) {
            TitleGrid(items: items)
        }
        .task(id: browse.changes) {
            let (page, failed) = await loadPage(app, "playlist") { try await $0.playlist(id) }
            if let page { items = page.entries.map(\.item) }
            problem = failed
            loading = false
        }
    }
}

/// Someone's picture and name, and the titles in the libraries they're in.
struct PersonView: View {
    @Environment(AppModel.self) private var app
    let id: Int64
    let name: String
    @State private var page: PersonPage?
    @State private var loading = true
    @State private var problem: String?

    var body: some View {
        PageScaffold(title: name, loading: loading, problem: problem, empty: page?.credits.isEmpty == true ? L("browse.person_empty") : nil) {
            if let page {
                if let known = page.person.knownFor, !known.isEmpty {
                    Text(known).foregroundStyle(ArcColor.muted)
                }
                TitleGrid(items: page.credits.map(\.item))
            }
        }
        .task {
            let (answer, failed) = await loadPage(app, "person") { try await $0.person(id) }
            page = answer ?? page
            problem = failed
            loading = false
        }
    }
}

/// A folder in an Other videos library: the folders in it, then its videos.
struct FolderView: View {
    @Environment(AppModel.self) private var app
    let library: Library
    let path: String
    let name: String
    @State private var page: FolderPage?
    @State private var loading = true
    @State private var problem: String?

    var body: some View {
        PageScaffold(title: name, loading: loading, problem: problem,
                     empty: page.map { $0.folders.isEmpty && $0.items.isEmpty } == true ? L("browse.folder_empty") : nil) {
            if let page { FolderContents(library: library, page: page) }
        }
        .task {
            let (answer, failed) = await loadPage(app, "folder") { try await $0.folders(libraryId: library.id, path: path) }
            page = answer ?? page
            problem = failed
            loading = false
        }
    }
}

/// A folder's folders (as tiles) and videos (as posters); shared by a library's Folders view.
struct FolderContents: View {
    @Environment(\.openRoute) private var openRoute
    let library: Library
    let page: FolderPage

    var body: some View {
        VStack(alignment: .leading, spacing: 56) {
            if !page.folders.isEmpty {
                LazyVGrid(columns: TitleGrid.columns, alignment: .leading, spacing: 56) {
                    ForEach(page.folders) { folder in
                        TileButton(title: folder.name, subtitle: L("browse.videos_count", folder.count), art: folder.cover) {
                            openRoute(.folder(library: library, path: folder.path, name: folder.name))
                        }
                    }
                }
            }
            if !page.items.isEmpty { TitleGrid(items: page.items) }
        }
    }
}

/// The profile's Watchlist, most recently added first.
struct WatchlistView: View {
    @Environment(AppModel.self) private var app
    @Environment(Browse.self) private var browse
    @State private var items: [Item] = []
    @State private var loading = true
    @State private var problem: String?

    var body: some View {
        PageScaffold(title: L("tab.watchlist"), loading: loading, problem: problem, empty: items.isEmpty ? L("browse.watchlist_empty") : nil) {
            TitleGrid(items: items)
        }
        .task(id: browse.changes) {
            let (answer, failed) = await loadPage(app, "watchlist") { try await $0.watchlist() }
            if let answer { items = answer }
            problem = failed
            loading = false
        }
    }
}

/// The profile's playlists, each with its first titles' pictures.
struct PlaylistsView: View {
    @Environment(AppModel.self) private var app
    @Environment(Browse.self) private var browse
    @Environment(\.openRoute) private var openRoute
    @State private var playlists: [PlaylistSummary] = []
    @State private var loading = true
    @State private var problem: String?

    var body: some View {
        PageScaffold(title: L("tab.playlists"), loading: loading, problem: problem, empty: playlists.isEmpty ? L("browse.playlists_empty") : nil) {
            LazyVGrid(columns: TitleGrid.columns, alignment: .leading, spacing: 56) {
                ForEach(playlists) { list in
                    TileButton(title: list.title, subtitle: L("browse.titles_count", list.count), art: list.images.first) {
                        openRoute(.playlist(id: list.id, title: list.title))
                    }
                }
            }
        }
        .task(id: browse.changes) {
            let (answer, failed) = await loadPage(app, "playlists") { try await $0.playlists() }
            if let answer { playlists = answer }
            problem = failed
            loading = false
        }
    }
}
