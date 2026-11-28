import ArcKit
import SwiftUI

/// Search across every library the profile can see, as the web's and the Apple TV's: films,
/// shows, episodes, collections, people and genres, following the typing after a short pause.
struct MobileSearchScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openRoute) private var openRoute
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var text = ""
    @State private var results: SearchResults?
    @State private var problem: String?

    var body: some View {
        let wide = sizeClass == .regular
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                if let problem {
                    MobileMessage(title: problem) { Task { await search() } }
                } else if let results, results.isEmpty {
                    MobileMessage(title: L("search.nothing", text.trimmingCharacters(in: .whitespaces)))
                } else if let results {
                    titles(L("search.movies"), results.movies, .poster)
                    titles(L("search.shows"), results.shows, .poster)
                    titles(L("search.episodes"), results.episodes, .thumb)
                    if !results.collections.isEmpty {
                        section(L("search.collections")) {
                            MobileCollectionGrid(collections: results.collections)
                        }
                    }
                    if !results.people.isEmpty {
                        section(L("search.people")) {
                            ScrollView(.horizontal) {
                                LazyHStack(alignment: .top, spacing: 16) {
                                    ForEach(results.people) { p in
                                        MobilePersonButton(name: p.name, detail: p.knownFor, image: p.image) {
                                            openRoute(.person(id: p.id, name: p.name))
                                        }
                                    }
                                }
                            }
                            .contentMargins(.horizontal, Metrics.margin(wide), for: .scrollContent)
                            .scrollIndicators(.hidden)
                        }
                    }
                    if !results.genres.isEmpty {
                        section(L("search.genres")) {
                            VStack(spacing: 0) {
                                ForEach(results.genres, id: \.self) { g in
                                    Button { openRoute(.genre(g)) } label: {
                                        HStack {
                                            Text(g.libraryName.map { "\(g.name) · \($0)" } ?? g.name).foregroundStyle(ArcColor.foreground)
                                            Spacer()
                                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(ArcColor.subtle)
                                        }
                                        .padding(.vertical, 12)
                                    }
                                    Divider()
                                }
                            }
                            .padding(.horizontal, Metrics.margin(wide))
                        }
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .navigationTitle(L("tab.search"))
        .background(PageWash())
        .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: L("search.prompt"))
        .autocorrectionDisabled()
        .task(id: text) { await search() }
    }

    @ViewBuilder private func titles(_ title: String, _ items: [Item], _ style: CardStyle) -> some View {
        if !items.isEmpty {
            MobileRow(title: title, cards: items.map { MediaCard(item: $0) }, style: style)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.weight(.bold)).padding(.horizontal, Metrics.margin(sizeClass == .regular))
            content()
        }
    }

    private func search() async {
        let q = text.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            results = nil
            problem = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(350))
        if Task.isCancelled { return }
        let (answer, failed) = await loadPage(app, "search") { try await $0.search(q) }
        if Task.isCancelled { return }
        if let answer { results = answer }
        problem = failed
    }
}

/// Someone in a round picture with their name and part under it (search, a title's cast).
struct MobilePersonButton: View {
    let name: String
    var detail: String?
    let image: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    ArcColor.surface2
                    if image == nil {
                        Text(initials).font(.title3.weight(.semibold)).foregroundStyle(ArcColor.muted)
                    } else {
                        ArtworkImage(path: image)
                    }
                }
                .frame(width: 84, height: 84)
                .clipShape(Circle())
                Text(name).font(.caption.weight(.semibold)).foregroundStyle(ArcColor.foreground).lineLimit(1)
                if let detail, !detail.isEmpty {
                    Text(detail).font(.caption2).foregroundStyle(ArcColor.muted).lineLimit(1)
                }
            }
            .frame(width: 96)
        }
        .buttonStyle(.plain)
    }

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }
}
