import ArcKit
import SwiftUI

/// A collection, laid out as a library's Browse page: its name at the top with a sort pill at
/// the right (Release Date, as Arc lists it, or Title), its overview, then the poster grid.
struct CollectionView: View {
    @Environment(AppModel.self) private var app
    @Environment(Browse.self) private var browse
    let id: String
    let title: String
    @State private var page: CollectionPage?
    @State private var loading = true
    @State private var problem: String?
    @State private var byTitle = false

    var body: some View {
        PageScaffold(title: page?.collection.title ?? title, loading: loading, problem: problem,
                     empty: page?.items.isEmpty == true ? L("browse.collection_empty") : nil,
                     accessory: (page?.items.count ?? 0) > 1 ? AnyView(sortPill) : nil) {
            if let overview = page?.collection.overview, !overview.isEmpty {
                Text(overview).font(.callout).foregroundStyle(ArcColor.muted).lineLimit(3).frame(maxWidth: 1100, alignment: .leading)
            }
            TitleGrid(items: items)
        }
        .task(id: browse.changes) {
            let (answer, failed) = await loadPage(app, "collection") { try await $0.collection(id) }
            page = answer ?? page
            problem = failed
            loading = false
        }
    }

    private var items: [Item] {
        let all = page?.items ?? []
        return byTitle ? all.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } : all
    }

    private var sortPill: some View {
        Menu {
            Picker(L("watchlist.sort"), selection: $byTitle) {
                Text(L("library.sort_released")).tag(false)
                Text(L("library.sort_title")).tag(true)
            }
        } label: {
            Label(L(byTitle ? "library.sort_title" : "library.sort_released"), systemImage: "arrow.up.arrow.down")
        }
        .arcGlassButton().buttonBorderShape(.capsule)
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

/// The profile's Watchlist: All, Movies or TV Shows, by Date Added (newest first, as Arc lists
/// it), Title or Release Date, from the pills at the right of the title.
struct WatchlistView: View {
    @Environment(AppModel.self) private var app
    @Environment(Browse.self) private var browse
    @State private var items: [Item] = []
    @State private var loading = true
    @State private var problem: String?
    @State private var kind: Kind = .all
    @State private var sort: Sort = .added

    enum Kind: CaseIterable { case all, movies, shows }
    enum Sort: CaseIterable { case added, title, released }

    var body: some View {
        PageScaffold(title: L("tab.watchlist"), loading: loading, problem: problem,
                     empty: items.isEmpty ? L("browse.watchlist_empty") : shown.isEmpty ? L("browse.watchlist_none_of_kind") : nil,
                     accessory: items.isEmpty ? nil : AnyView(controls)) {
            TitleGrid(items: shown)
        }
        .task(id: browse.changes) {
            let (answer, failed) = await loadPage(app, "watchlist") { try await $0.watchlist() }
            if let answer { items = answer }
            problem = failed
            loading = false
        }
    }

    private var shown: [Item] {
        let kept = items.filter { item in
            switch kind {
            case .all: return true
            case .movies: return item.kind == "movie"
            case .shows: return item.kind != "movie"
            }
        }
        switch sort {
        case .added: return kept
        case .title: return kept.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        // Newest first; titles without a date go last.
        case .released: return kept.sorted { ($0.releaseDate ?? $0.year.map(String.init) ?? "") > ($1.releaseDate ?? $1.year.map(String.init) ?? "") }
        }
    }

    private var controls: some View {
        HStack(spacing: 20) {
            Menu {
                Picker(L("watchlist.show"), selection: $kind) {
                    ForEach(Kind.allCases, id: \.self) { Text(name($0)).tag($0) }
                }
            } label: {
                Text(name(kind)).padding(.horizontal, 8)
            }
            .arcGlassButton().buttonBorderShape(.capsule)
            Menu {
                Picker(L("watchlist.sort"), selection: $sort) {
                    ForEach(Sort.allCases, id: \.self) { Text(name($0)).tag($0) }
                }
            } label: {
                Text(name(sort)).padding(.horizontal, 8)
            }
            .arcGlassButton().buttonBorderShape(.capsule)
        }
    }

    private func name(_ kind: Kind) -> String {
        switch kind {
        case .all: return L("library.all")
        case .movies: return L("watchlist.movies")
        case .shows: return L("watchlist.shows")
        }
    }

    private func name(_ sort: Sort) -> String {
        switch sort {
        case .added: return L("library.sort_added")
        case .title: return L("library.sort_title")
        case .released: return L("library.sort_released")
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
