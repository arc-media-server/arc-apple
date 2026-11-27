import ArcKit
import SwiftUI

/// A library: its Recommended rows under a hero (first, as Plex opens a library), all its
/// titles as a poster grid with the web's sorts and filters (genre, decade, resolution,
/// unwatched), its collections, or (Other videos, which have no Recommended) its folders.
struct LibraryView: View {
    @Environment(AppModel.self) private var app
    @Environment(Browse.self) private var browse
    @Environment(\.openRoute) private var openRoute
    let library: Library

    enum Show: Hashable { case recommended, titles, collections, folders }

    @State private var show: Show
    @State private var recommended: [LoadedRow] = []
    @State private var query = LibraryQuery()
    @State private var items: [Item] = []
    @State private var total = 0
    @State private var loadingMore = false
    /// The A–Z bar's letters (sorted by title), a jump under way, and the title it lands on.
    @State private var letters: [LetterJump] = []
    @State private var jumping = false
    @State private var jumpTarget: String?
    @State private var facets: Facets?
    @State private var collections: [CollectionSummary] = []
    @State private var folders: FolderPage?
    @State private var loading = true
    @State private var problem: String?

    private static let page = 60
    private var isVideos: Bool { library.kind == "videos" }

    init(library: Library) {
        self.library = library
        _show = State(initialValue: library.kind == "videos" ? .titles : .recommended)
    }

    var body: some View {
        Group {
            if show == .recommended {
                recommendedPage
            } else {
                browsePage
            }
        }
        .task(id: Reload(show: show, query: query, changes: browse.changes)) { await reload() }
        .task { await loadFacets() }
    }

    /// Recommended: the hero and rows, as Home, with the pill bar above.
    @ViewBuilder private var recommendedPage: some View {
        if loading {
            VStack(alignment: .leading) { header; Spacer() }.padding(.horizontal, 80).padding(.vertical, Self.headerTop)
                .overlay { ProgressView() }
        } else if let problem {
            VStack(alignment: .leading) {
                header
                RowsMessage(title: problem, message: "") { Task { await reload() } }
            }
            .padding(.horizontal, 80).padding(.vertical, Self.headerTop)
        } else if recommended.isEmpty {
            VStack(alignment: .leading) {
                header
                RowsMessage(title: L("library.recommended_empty_title"), message: L("library.recommended_empty"), retry: nil)
            }
            .padding(.horizontal, 80).padding(.vertical, Self.headerTop)
        } else {
            HeroRows(rows: recommended, headerHeight: 90) {
                header.padding(.horizontal, 80).padding(.top, Self.headerTop)
            }
        }
    }

    /// Browse, Collections and Folders scroll under the pill bar; sorted by title, Browse has the
    /// A–Z bar down the right, staying in place as the titles scroll.
    private var browsePage: some View {
        ScrollViewReader { proxy in
            HStack(alignment: .top, spacing: 0) {
                browseScroll
                if showsLetterBar {
                    LetterBar(letters: letters) { letter in Task { await jump(to: letter, proxy) } }
                        // The grid keeps its width: 24 + the bar's 44 + 12 is the 80 it had at the right.
                        .padding(.top, 96)
                        .padding(.trailing, 12)
                }
            }
        }
    }

    /// The pill bar's distance from the top: close, so two rows of posters fit under it with
    /// their names and years (owner, 27 November).
    static let headerTop: CGFloat = 0

    private var showsLetterBar: Bool {
        show == .titles && !loading && problem == nil && query.showsLetters && letters.count > 1
    }

    private var browseScroll: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 24) {
                header
                if loading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 400)
                } else if let problem {
                    VStack(spacing: 20) {
                        Text(problem).foregroundStyle(ArcColor.error)
                        Button(L("common.retry")) { Task { await reload() } }.arcGlassButton()
                    }
                    .frame(maxWidth: .infinity, minHeight: 400)
                } else {
                    content
                }
            }
            .padding(.leading, 80)
            .padding(.trailing, showsLetterBar ? 24 : 80)
            .padding(.top, Self.headerTop)
            .padding(.bottom, 40)
        }
    }

    /// What the page reloads for.
    private struct Reload: Equatable {
        let show: Show
        let query: LibraryQuery
        let changes: Int
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 24) {
            showTabs
            Spacer()
            if show == .titles {
                sortMenu.arcGlassButton().buttonBorderShape(.capsule)
                filterMenu.arcGlassButton().buttonBorderShape(.capsule)
            }
        }
        .focusSection()
    }

    /// Recommended, Browse, Collections and (Other videos) Folders, each its own glass pill as
    /// Sort and Filter are, the one showing white with black text (owner, 27 November). The
    /// sidebar says which library it is.
    private var showTabs: some View {
        HStack(spacing: 16) {
            if !isVideos { showTab(L("library.recommended"), .recommended) }
            showTab(L("library.browse"), .titles)
            showTab(L("library.collections"), .collections)
            if isVideos { showTab(L("library.folders"), .folders) }
        }
        .focusSection()
    }

    private func showTab(_ title: String, _ value: Show) -> some View {
        Button(title) { show = value }
            .arcGlassButton(prominent: show == value)
            .buttonBorderShape(.capsule)
            .accessibilityAddTraits(show == value ? .isSelected : [])
    }

    private var sortMenu: some View {
        Menu {
            ForEach(LibrarySort.allCases, id: \.self) { sort in
                Button {
                    if query.sort == sort { query.reversed.toggle() } else { query.sort = sort; query.reversed = false }
                } label: {
                    if query.sort == sort {
                        Label(sortName(sort), systemImage: query.reversed ? "arrow.up" : "arrow.down")
                    } else {
                        Text(sortName(sort))
                    }
                }
            }
        } label: {
            Label(sortName(query.sort), systemImage: "arrow.up.arrow.down")
        }
    }

    private var filterName: String {
        let chosen = [query.unwatchedOnly ? L("library.unwatched_short") : nil, query.genre,
                      query.decade.map { L("library.decade_value", $0) }, query.resolution.map { resolutionName($0) },
                      query.watchState.map(watchStateName), query.dynamicRange.map(dynamicRangeName),
                      query.videoCodec.map(Quality.videoCodec), query.audioCodec.map { Quality.audioCodec($0) ?? $0 },
                      query.audioChannels.map(channelsName)].compactMap { $0 }
        switch chosen.count {
        case 0: return L("library.all")
        case 1: return chosen[0]
        default: return L("library.filtered_count", chosen.count)
        }
    }

    private var filterMenu: some View {
        Menu {
            // Unwatched Only and Watch Status exclude each other, as Arc requires: one turns the other off.
            Toggle(L("library.unwatched"), isOn: Binding(get: { query.unwatchedOnly }, set: { query.setUnwatched($0) }))
            Picker(L("library.watch_status"), selection: Binding(get: { query.watchState }, set: { query.setWatchState($0) })) {
                Text(L("library.any")).tag(String?.none)
                Text(L("library.watch_played")).tag(Optional("played"))
                Text(L("library.watch_unstarted")).tag(Optional("unstarted"))
            }
            .pickerStyle(.menu)
            facetMenu(L("library.genre"), values: facets?.genres ?? [], selection: $query.genre) { $0 }
            facetMenu(L("library.decade"), values: facets?.decades ?? [], selection: $query.decade) { L("library.decade_value", $0) }
            if !isVideos && library.kind != "shows" {
                facetMenu(L("library.resolution"), values: facets?.resolutions ?? [], selection: $query.resolution) { resolutionName($0) }
            }
            // What the files are: offered only where the library has more than one (as the web's).
            offeredMenu(L("library.hdr"), values: facets?.dynamicRanges, selection: $query.dynamicRange, name: dynamicRangeName)
            offeredMenu(L("library.video_format"), values: facets?.videoCodecs, selection: $query.videoCodec, name: Quality.videoCodec)
            offeredMenu(L("library.audio_format"), values: facets?.audioCodecs, selection: $query.audioCodec) { Quality.audioCodec($0) ?? $0 }
            offeredMenu(L("library.audio_channels"), values: facets?.audioChannels, selection: $query.audioChannels, name: channelsName, mostFirst: true)
            if query.filtered {
                Button(L("library.clear_filters"), role: .destructive) { query = query.cleared }
            }
        } label: {
            // The button names what's shown: All, Unwatched, a genre, or Filtered for several.
            Label(filterName, systemImage: query.filtered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
    }

    @ViewBuilder
    private func facetMenu(_ title: String, values: [FacetValue], selection: Binding<String?>, name: @escaping (String) -> String) -> some View {
        if !values.isEmpty {
            Picker(title, selection: selection) {
                Text(L("library.any")).tag(String?.none)
                ForEach(values) { v in Text(name(v.value)).tag(Optional(v.value)) }
            }
            .pickerStyle(.menu)
        }
    }

    /// A media filter's list: Any, then the library's values (or the one chosen), when there's a choice.
    @ViewBuilder
    private func offeredMenu(_ title: String, values: [FacetValue]?, selection: Binding<String?>,
                             name: @escaping (String) -> String, mostFirst: Bool = false) -> some View {
        let offered = Facets.offered(values ?? [], chosen: selection.wrappedValue)
        let shown = mostFirst ? offered.sorted { (Int($0) ?? 0) > (Int($1) ?? 0) } : offered
        if !shown.isEmpty {
            Picker(title, selection: selection) {
                Text(L("library.any")).tag(String?.none)
                ForEach(shown, id: \.self) { v in Text(name(v)).tag(Optional(v)) }
            }
            .pickerStyle(.menu)
        }
    }

    private func watchStateName(_ value: String) -> String {
        value == "played" ? L("library.watch_played") : L("library.watch_unstarted")
    }

    private func dynamicRangeName(_ value: String) -> String { Quality.dynamicRange(value) ?? L("library.hdr_unknown") }

    private func channelsName(_ value: String) -> String {
        let n = Int(value)
        return n == 2 ? L("library.stereo") : n == 1 ? L("library.mono") : Quality.channels(n) ?? value
    }

    @ViewBuilder private var content: some View {
        switch show {
        case .recommended:
            EmptyView() // shown by recommendedPage
        case .titles:
            if items.isEmpty {
                Text(query.filtered ? L("library.nothing_matches") : L("library.empty")).foregroundStyle(ArcColor.muted)
                    .frame(maxWidth: .infinity, minHeight: 400)
            } else {
                TitleGrid(items: items, target: jumpTarget) { Task { await loadMore() } }
                if loadingMore { ProgressView().frame(maxWidth: .infinity) }
            }
        case .collections:
            if collections.isEmpty {
                Text(L("library.no_collections")).foregroundStyle(ArcColor.muted).frame(maxWidth: .infinity, minHeight: 400)
            } else {
                LazyVGrid(columns: TitleGrid.columns, alignment: .leading, spacing: TitleGrid.rowGap) {
                    ForEach(collections) { c in
                        TileButton(title: c.title, subtitle: L("browse.titles_count", c.count), art: c.images?.primary) {
                            openRoute(.collection(id: c.id, title: c.title))
                        }
                    }
                }
            }
        case .folders:
            if let folders { FolderContents(library: library, page: folders) }
        }
    }

    private func reload() async {
        problem = nil
        let started = Date()
        switch show {
        case .recommended:
            let (answer, failed) = await loadPage(app, "library recommended") { try await $0.recommended(libraryId: library.id) }
            if let answer {
                recommended = answer.rows.map { row in
                    LoadedRow(id: row.id, title: rowTitle(row), style: rowStyle(row),
                              cards: row.items.map { MediaCard(item: $0) }, continueRow: row.type == "continue")
                }.filter { !$0.cards.isEmpty }
                ArcLogApp.debug("library \(library.id): \(recommended.count) recommended rows in \(Int(Date().timeIntervalSince(started) * 1000)) ms")
            }
            problem = failed
        case .titles:
            let params = query.parameters(library: library, offset: 0, limit: Self.page, letters: true)
            let (page, failed) = await loadPage(app, "library") { try await $0.items(params) }
            if let page {
                items = page.items
                total = page.total
                letters = letterJumps(page.letters, reversed: query.reversed)
                jumpTarget = nil
                ArcLogApp.debug("library \(library.id): \(page.items.count) of \(page.total) titles in \(Int(Date().timeIntervalSince(started) * 1000)) ms")
            }
            problem = failed
        case .collections:
            let (answer, failed) = await loadPage(app, "library collections") { try await $0.collections(libraryId: library.id) }
            if let answer { collections = answer }
            problem = failed
        case .folders:
            let (answer, failed) = await loadPage(app, "library folders") { try await $0.folders(libraryId: library.id, path: "") }
            if let answer { folders = answer }
            problem = failed
        }
        loading = false
    }

    /// The next page of titles, once the grid nears its end.
    private func loadMore() async {
        guard !loadingMore, !jumping, items.count < total, show == .titles else { return }
        loadingMore = true
        defer { loadingMore = false }
        let params = query.parameters(library: library, offset: items.count, limit: Self.page)
        let (page, failed) = await loadPage(app, "library page") { try await $0.items(params) }
        guard let page, params["offset"] == String(items.count) else {
            if failed != nil { ArcLogApp.debug("library \(library.id): a page failed; it's asked for again on scrolling") }
            return
        }
        let have = Set(items.map(\.id))
        items += page.items.filter { !have.contains($0.id) }
        total = page.total
    }

    /// Moves to a letter's first title: loads the titles up to it (and a page more) if the grid
    /// hasn't reached it yet, scrolls there and gives it the focus.
    private func jump(to letter: LetterJump, _ proxy: ScrollViewProxy) async {
        guard !jumping, show == .titles else { return }
        jumping = true
        defer { jumping = false }
        let started = Date(), had = items.count
        let asked = query
        for chunk in pagesToReach(letter.offset, have: items.count, total: total, page: Self.page) {
            // A page that arrives after the grid moved on (another sort, a reload) is dropped.
            guard chunk.offset == items.count, query == asked else { break }
            let params = query.parameters(library: library, offset: chunk.offset, limit: chunk.limit)
            let (page, _) = await loadPage(app, "library letter") { try await $0.items(params) }
            guard let page, query == asked, chunk.offset == items.count else { break }
            let have = Set(items.map(\.id))
            items += page.items.filter { !have.contains($0.id) }
            total = page.total
            if page.items.isEmpty { break }
        }
        guard items.indices.contains(letter.offset) else {
            ArcLogApp.debug("library \(library.id): a letter's titles didn't load")
            return
        }
        let id = items[letter.offset].id
        ArcLogApp.debug("library \(library.id): jumped to a letter, \(items.count - had) more titles in \(Int(Date().timeIntervalSince(started) * 1000)) ms")
        proxy.scrollTo(id, anchor: .top)
        // A moment later, once the grid has built the card it scrolled to.
        jumpTarget = nil
        try? await Task.sleep(for: .milliseconds(100))
        jumpTarget = id
    }

    private func loadFacets() async {
        let (answer, _) = await loadPage(app, "library filters") { try await $0.facets(libraryId: library.id) }
        facets = answer ?? facets
    }

    private func rowTitle(_ row: RecommendedRow) -> String {
        switch recommendedTitle(row, libraryName: library.name, libraryKind: library.kind) {
        case .key(let key, let name?): return L(key, name)
        case .key(let key, nil): return L(key)
        case .server(let title): return title
        }
    }

    /// The shared layout's look, else posters, with wide pictures for episodes and what's in progress.
    private func rowStyle(_ row: RecommendedRow) -> CardStyle {
        if let saved = cardStyle(saved: row.style) { return saved }
        return row.type == "continue" || (row.type == "recently_watched" && library.kind == "shows") ? .thumb : .poster
    }

    private func sortName(_ sort: LibrarySort) -> String {
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

    private func resolutionName(_ value: String) -> String {
        switch value {
        case "4k": return "4K"
        case "1080": return "1080p"
        case "720": return "720p"
        case "sd": return "SD"
        default: return value
        }
    }
}
