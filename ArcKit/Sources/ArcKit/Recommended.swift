import Foundation

/// One row of a library's Recommended view (GET /libraries/{id}/recommended): what it is (type)
/// and what it's about, so the app titles it in the viewer's language, with Arc's English title
/// for a type the app doesn't know yet.
public struct RecommendedRow: Codable, Sendable, Identifiable {
    public let id: String
    @Default<Defaults.Empty> public var type: String
    @Default<Defaults.Empty> public var title: String
    public var name: String?
    public var genre: String?
    public var personId: Int64?
    public var role: String?
    /// poster, thumb or arc (the shared layout's look); empty for automatic.
    @Default<Defaults.Empty> public var style: String
    @Default<Defaults.List<Item>> public var items: [Item]

    public init(id: String, type: String, title: String = "", name: String? = nil, role: String? = nil, items: [Item] = []) {
        self.id = id
        self.type = type
        self.title = title
        self.name = name
        self.role = role
        self.items = items
    }
}

public struct RecommendedPage: Codable, Sendable {
    @Default<Defaults.List<RecommendedRow>> public var rows: [RecommendedRow]
}

/// How to title a Recommended row: a string key (the web's library:recommendedRows) and the name
/// it takes, or Arc's own title when the type is new to this app.
public enum RecommendedTitle: Equatable, Sendable {
    case key(String, String?)
    case server(String)
}

/// The web's recommendedTitle (web/src/pages/Library.tsx): shows libraries say Shows and
/// Episodes where films say Movies; a person's row says "with" for actors and "by" for directors.
public func recommendedTitle(_ row: RecommendedRow, libraryName: String, libraryKind: String) -> RecommendedTitle {
    let shows = libraryKind == "shows"
    let name = row.name ?? ""
    switch row.type {
    case "continue": return .key("rec.continue", nil)
    case "recently_released": return .key("rec.recently_released", nil)
    case "recently_added": return .key("rec.recently_added", row.name ?? libraryName)
    case "start_watching": return .key("rec.start_watching", nil)
    case "because_you_watched": return .key("rec.because_you_watched", name)
    case "top_rated": return .key(shows ? "rec.top_rated_shows" : "rec.top_rated_movies", nil)
    case "recently_watched": return .key(shows ? "rec.recently_watched_episodes" : "rec.recently_watched", nil)
    case "rediscover": return .key("rec.rediscover", nil)
    case "more_in_genre": return .key("rec.more_in_genre", name)
    case "top_in_genre": return .key(shows ? "rec.top_shows_in_genre" : "rec.top_movies_in_genre", name)
    case "top_by_person":
        if row.role == "director" { return .key(shows ? "rec.top_shows_by" : "rec.top_movies_by", name) }
        return .key(shows ? "rec.top_shows_with" : "rec.top_movies_with", name)
    case "top_unwatched": return .key("rec.top_unwatched", nil)
    default: return .server(row.title)
    }
}

extension ArcAPI {
    /// A library's Recommended rows for the profile (not for Other videos libraries).
    public func recommended(libraryId: Int64) async throws -> RecommendedPage {
        try await get("libraries/\(libraryId)/recommended", route: "libraries/{id}/recommended")
    }
}
