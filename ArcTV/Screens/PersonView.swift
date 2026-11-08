import ArcKit
import SwiftUI

/// Someone's page: their picture and name over the background of the title in focus, then rows
/// of what they're in across the libraries (Movies, TV Shows, and what they made behind the
/// camera), newest first. The focused title's year and their part in it show beside the name.
struct PersonView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openRoute) private var openRoute
    let id: Int64
    let name: String
    @State private var page: PersonPage?
    @State private var loading = true
    @State private var problem: String?
    @FocusState private var focused: String?

    private struct Row: Identifiable {
        let id: String
        let title: String
        let credits: [PersonCredit]
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            backdrop
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let problem {
                Text(problem).foregroundStyle(ArcColor.error).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 44) {
                        header
                        if rows.isEmpty {
                            Text(L("browse.person_empty")).foregroundStyle(ArcColor.muted).padding(.horizontal, 80)
                        }
                        ForEach(rows) { row in
                            VStack(alignment: .leading, spacing: 16) {
                                Text(row.title).font(.title3.weight(.semibold)).padding(.horizontal, 80)
                                ScrollView(.horizontal) {
                                    LazyHStack(alignment: .top, spacing: 36) {
                                        ForEach(row.credits, id: \.item.id) { credit in
                                            MediaCardView(card: MediaCard(item: credit.item), style: .poster,
                                                          focus: $focused, focusKey: row.id + "|" + credit.item.id) {
                                                openRoute(.item(credit.item))
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 80)
                                    .padding(.vertical, 20)
                                }
                                .scrollClipDisabled()
                            }
                        }
                    }
                    .padding(.bottom, 60)
                }
            }
        }
        .task {
            let (answer, failed) = await loadPage(app, "person") { try await $0.person(id) }
            page = answer ?? page
            problem = failed
            loading = false
            if let first = rows.first, let credit = first.credits.first {
                Task { @MainActor in focused = first.id + "|" + credit.item.id }
            }
        }
    }

    /// The picture, name and line at the top; the first row peeks up under it.
    private var header: some View {
        HStack(alignment: .bottom, spacing: 44) {
            ZStack {
                ArcColor.surface2
                if let image = page?.person.image {
                    ArtworkImage(path: image)
                } else {
                    Text(initials).font(.system(size: 72, weight: .semibold)).foregroundStyle(ArcColor.muted)
                }
            }
            .frame(width: 240, height: 240)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 2))
            .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
            VStack(alignment: .leading, spacing: 12) {
                Text(page?.person.name ?? name).font(.system(size: 64, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
                Text(summary).font(.callout.weight(.medium)).foregroundStyle(.white.opacity(0.85))
                // The focused title and their part in it.
                if let credit = focusedCredit {
                    Text(part(credit)).font(.callout).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                        .animation(.easeInOut(duration: 0.2), value: credit.item.id)
                }
            }
            .padding(.bottom, 20)
        }
        .frame(height: 480, alignment: .bottomLeading)
        .padding(.horizontal, 80)
    }

    /// "Acting · 14 titles in your libraries".
    private var summary: String {
        var parts: [String] = []
        if let known = page?.person.knownFor, !known.isEmpty { parts.append(known) }
        let count = Set(page?.credits.map(\.item.id) ?? []).count
        parts.append(count == 1 ? L("person.titles_one") : L("person.titles_count", count))
        return parts.joined(separator: " · ")
    }

    /// "Heat (1995) · Lt. Vincent Hanna", or "· Director" for a part behind the camera.
    private func part(_ credit: PersonCredit) -> String {
        var line = credit.item.title
        if let year = credit.item.year { line += " (\(year))" }
        if let character = credit.character, !character.isEmpty {
            line += " · " + L("person.as", character)
        } else if let role = credit.roles.first(where: { $0 != "actor" }) {
            line += " · " + roleName(role)
        }
        return line
    }

    private func roleName(_ role: String) -> String {
        switch role {
        case "director": return L("person.role_director")
        case "writer": return L("person.role_writer")
        case "producer": return L("person.role_producer")
        default: return role.capitalized
        }
    }

    /// Movies and TV Shows they act in, then everything they made behind the camera; newest first.
    private var rows: [Row] {
        guard let page else { return [] }
        let newest = page.credits.sorted { Self.date($0.item) > Self.date($1.item) }
        func acting(_ c: PersonCredit) -> Bool { c.roles.isEmpty || c.roles.contains("actor") }
        var seen: Set<String> = []
        func unique(_ list: [PersonCredit]) -> [PersonCredit] {
            seen = []
            return list.filter { seen.insert($0.item.id).inserted }
        }
        var out: [Row] = []
        let movies = unique(newest.filter { acting($0) && $0.item.kind == "movie" })
        let shows = unique(newest.filter { acting($0) && $0.item.kind != "movie" })
        let crew = unique(newest.filter { !acting($0) })
        if !movies.isEmpty { out.append(Row(id: "movies", title: L("person.movies"), credits: movies)) }
        if !shows.isEmpty { out.append(Row(id: "shows", title: L("person.shows"), credits: shows)) }
        if !crew.isEmpty { out.append(Row(id: "crew", title: L("person.behind_camera"), credits: crew)) }
        return out
    }

    private static func date(_ item: Item) -> String {
        item.releaseDate ?? item.year.map(String.init) ?? ""
    }

    private var focusedCredit: PersonCredit? {
        let all = rows.flatMap { row in row.credits.map { (row.id + "|" + $0.item.id, $0) } }
        if let key = focused, let hit = all.first(where: { $0.0 == key }) { return hit.1 }
        return all.first?.1
    }

    /// The focused title's background, faded into the page at the left and bottom (as Home's).
    private var backdrop: some View {
        let art = focusedCredit.flatMap { MediaCard(item: $0.item).backdrop }
        return ArtworkImage(path: art)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(art == nil ? 0 : 0.85)
            .overlay(LinearGradient(stops: [.init(color: ArcColor.background.opacity(0.9), location: 0), .init(color: .clear, location: 0.7)],
                                    startPoint: .leading, endPoint: .trailing))
            .overlay(LinearGradient(stops: [.init(color: .clear, location: 0.3), .init(color: ArcColor.background.opacity(0.8), location: 0.65),
                                            .init(color: ArcColor.background, location: 1)], startPoint: .top, endPoint: .bottom))
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.5), value: art)
    }

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }
}
