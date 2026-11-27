import ArcKit
import SwiftUI

/// Search across every library the profile can see: titles, episodes, collections, people and genres,
/// as the web's search. Arc forgives accents and small typos. Results follow the typing after a
/// short pause.
struct SearchView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openRoute) private var openRoute
    @State private var text = ""
    @State private var results: SearchResults?
    @State private var problem: String?
    @FocusState private var focused: String?

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 48) {
                if let problem {
                    Text(problem).foregroundStyle(ArcColor.error).padding(.horizontal, 80)
                } else if let results, results.isEmpty {
                    Text(L("search.nothing", text)).foregroundStyle(ArcColor.muted).padding(.horizontal, 80)
                } else if let results {
                    titles(L("search.movies"), results.movies)
                    titles(L("search.shows"), results.shows)
                    episodes(results.episodes)
                    collections(results.collections)
                    people(results.people)
                    genres(results.genres)
                }
            }
            .padding(.vertical, 40)
        }
        .searchable(text: $text, prompt: L("search.prompt"))
        .task(id: text) { await search() }
    }

    @ViewBuilder
    private func titles(_ title: String, _ items: [Item]) -> some View {
        if !items.isEmpty {
            row(title) {
                ForEach(items) { item in
                    MediaCardView(card: MediaCard(item: item), style: .poster, focus: $focused, focusKey: title + item.id) { openRoute(.item(item)) }
                }
            }
        }
    }

    @ViewBuilder
    private func episodes(_ items: [Item]) -> some View {
        if !items.isEmpty {
            row(L("search.episodes")) {
                ForEach(items) { item in
                    MediaCardView(card: MediaCard(item: item), style: .thumb, focus: $focused, focusKey: "ep" + item.id) { openRoute(.item(item)) }
                }
            }
        }
    }

    @ViewBuilder
    private func collections(_ list: [CollectionSummary]) -> some View {
        if !list.isEmpty {
            row(L("search.collections")) {
                ForEach(list) { c in
                    TileButton(title: c.title, subtitle: L("browse.titles_count", c.count), art: c.images?.primary) {
                        openRoute(.collection(id: c.id, title: c.title))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func people(_ list: [Person]) -> some View {
        if !list.isEmpty {
            row(L("search.people")) {
                ForEach(list) { p in
                    PersonButton(name: p.name, detail: p.knownFor, image: p.image) { openRoute(.person(id: p.id, name: p.name)) }
                }
            }
        }
    }

    @ViewBuilder
    private func genres(_ list: [GenreMatch]) -> some View {
        if !list.isEmpty {
            row(L("search.genres")) {
                ForEach(list, id: \.self) { genre in
                    TileButton(title: genre.name, subtitle: genre.libraryName, art: nil, wide: true) {
                        openRoute(.genre(genre))
                    }
                }
            }
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title).font(.title3.weight(.semibold)).padding(.horizontal, 80)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 40) { content() }
                    .padding(.horizontal, 80)
                    .padding(.vertical, 24)
            }
            .scrollClipDisabled()
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
struct PersonButton: View {
    let name: String
    var detail: String?
    let image: String?
    /// The page's focus, when it follows which person has it (the title page's first row).
    var focus: FocusState<String?>.Binding? = nil
    var focusKey = ""
    let action: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if let focus {
                button.focused(focus, equals: focusKey)
            } else {
                button
            }
            Text(name).font(.caption).lineLimit(1)
            if let detail, !detail.isEmpty { Text(detail).font(.caption2).foregroundStyle(ArcColor.muted).lineLimit(1) }
        }
        .frame(width: 200)
    }

    private var button: some View {
            Button(action: action) {
                ZStack {
                    ArcColor.surface2
                    if image == nil {
                        Text(initials).font(.system(size: 48, weight: .semibold)).foregroundStyle(ArcColor.muted)
                    } else {
                        ArtworkImage(path: image)
                    }
                }
                .frame(width: 180, height: 180)
                .clipShape(Circle())
            }
            .buttonStyle(PersonCircleStyle())
    }

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }
}

/// A person's round picture: the whole circle grows and lifts on focus, as a card does (tvOS's
/// card style lifts a square, which a circular clip turned into the photo zooming inside a
/// circle that stayed still).
struct PersonCircleStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(isFocused ? 1.12 : configuration.isPressed ? 0.96 : 1)
            .shadow(color: .black.opacity(isFocused ? 0.5 : 0), radius: 18, y: 12)
            .animation(.easeOut(duration: 0.18), value: isFocused)
    }
}
