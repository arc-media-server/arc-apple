import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Browsing beyond Home: libraries with sort and filters, collections, folders, playlists,
// people, search, and the card actions (watched, Watchlist), with the profile's preferences.

/// Someone in a title's cast or crew (items/{id} "credits").
public struct Credit: Codable, Sendable, Hashable, Identifiable {
    public let personId: Int64
    public let name: String
    /// actor, director, writer…
    @Default<Defaults.Empty> public var role: String
    public var character: String?
    public var image: String?
    public var id: String { "\(personId):\(role):\(character ?? "")" }
}

/// A count of titles with one value of a filter (libraries/{id}/facets).
public struct FacetValue: Codable, Sendable, Hashable, Identifiable {
    public let value: String
    @Default<Defaults.Zero> public var count: Int
    public var id: String { value }
}

public struct Facets: Codable, Sendable {
    @Default<Defaults.List<FacetValue>> public var genres: [FacetValue]
    @Default<Defaults.List<FacetValue>> public var decades: [FacetValue]
    @Default<Defaults.List<FacetValue>> public var resolutions: [FacetValue]
}

/// A collection as listed (libraries/{id}/collections, search).
public struct CollectionSummary: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    @Default<Defaults.Zero> public var count: Int
    public var images: Images?
}

/// A folder in an Other videos library (libraries/{id}/folders).
public struct Folder: Codable, Sendable, Hashable, Identifiable {
    public let name: String
    public let path: String
    @Default<Defaults.Zero> public var count: Int
    public var cover: String?
    public var id: String { path }
}

public struct FolderPage: Codable, Sendable {
    @Default<Defaults.Empty> public var path: String
    @Default<Defaults.List<Folder>> public var folders: [Folder]
    @Default<Defaults.List<Item>> public var items: [Item]
}

public struct PlaylistSummary: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    @Default<Defaults.Zero> public var count: Int
    @Default<Defaults.List<String>> public var images: [String]
}

public struct Person: Codable, Sendable, Hashable, Identifiable {
    public let id: Int64
    public let name: String
    public var image: String?
    public var knownFor: String?
}

public struct PersonCredit: Codable, Sendable {
    public let item: Item
    public var character: String?
    @Default<Defaults.List<String>> public var roles: [String]
}

public struct PersonPage: Codable, Sendable {
    public let person: Person
    @Default<Defaults.List<PersonCredit>> public var credits: [PersonCredit]
}

/// GET /search: titles, episodes, collections and people that match.
public struct SearchResults: Codable, Sendable {
    @Default<Defaults.List<Item>> public var movies: [Item]
    @Default<Defaults.List<Item>> public var shows: [Item]
    @Default<Defaults.List<Item>> public var episodes: [Item]
    @Default<Defaults.List<CollectionSummary>> public var collections: [CollectionSummary]
    @Default<Defaults.List<Person>> public var people: [Person]

    public var isEmpty: Bool { movies.isEmpty && shows.isEmpty && episodes.isEmpty && collections.isEmpty && people.isEmpty }
}

/// How a library's grid is sorted, as the web's library page offers (the value /items takes).
public enum LibrarySort: String, CaseIterable, Sendable {
    case title, added, released = "release", year, rating, runtime, lastPlayed = "watched"
}

/// A library grid's sort and filters, as /items query parameters.
public struct LibraryQuery: Sendable, Hashable {
    public var sort: LibrarySort = .title
    /// Z to A, newest first, and so on: the sort's other way round.
    public var reversed = false
    public var unwatchedOnly = false
    public var genre: String?
    public var decade: String?
    public var resolution: String?

    public init() {}

    /// The /items parameters for `library`'s grid, `limit` titles from `offset`.
    public func parameters(library: Library, offset: Int, limit: Int) -> [String: String] {
        var p = ["library_id": String(library.id), "kind": library.kind == "shows" ? "series" : "movie",
                 "sort": sort.rawValue, "offset": String(offset), "limit": String(limit)]
        if reversed { p["reverse"] = "1" }
        if unwatchedOnly { p["unwatched"] = "1" }
        if let genre { p["genre"] = genre }
        if let decade { p["decade"] = decade }
        if let resolution { p["resolution"] = resolution }
        return p
    }

    public var filtered: Bool { unwatchedOnly || genre != nil || decade != nil || resolution != nil }
}

extension ArcAPI {
    public func facets(libraryId: Int64) async throws -> Facets {
        try await get("libraries/\(libraryId)/facets", route: "libraries/{id}/facets")
    }

    public func collections(libraryId: Int64) async throws -> [CollectionSummary] {
        try await get("libraries/\(libraryId)/collections", route: "libraries/{id}/collections")
    }

    /// An Other videos library's folder at `path` ("" for the top).
    public func folders(libraryId: Int64, path: String) async throws -> FolderPage {
        let query = path.isEmpty ? "" : "?path=\(enc(path))"
        return try await get("libraries/\(libraryId)/folders\(query)", route: "libraries/{id}/folders")
    }

    public func playlists() async throws -> [PlaylistSummary] { try await get("playlists") }

    public func person(_ id: Int64) async throws -> PersonPage {
        try await get("people/\(id)", route: "people/{id}")
    }

    public func similar(_ itemId: String) async throws -> [Item] {
        try await get("items/\(enc(itemId))/similar", route: "items/{id}/similar")
    }

    public func search(_ query: String) async throws -> SearchResults {
        try await get("search?q=\(enc(query))", route: "search")
    }

    /// Marks a title watched or unwatched (a show: all its episodes).
    public func setPlayed(_ itemId: String, _ played: Bool) async throws {
        try await sendJSON("PUT", "items/\(enc(itemId))/played", ["played": .bool(played)], route: "items/{id}/played")
    }

    /// Marks one season of a show watched or unwatched: the season as the profile's episode order
    /// numbers it, as `series/{id}/seasons` lists it.
    public func setPlayed(seriesId: String, seasonNumber: Int, _ played: Bool) async throws {
        let route = "items/{id}/played"
        let body = try ArcJSON.encoder.encode(SeasonPlayed(played: played, seasonNumber: seasonNumber))
        let (status, data) = try await raw("PUT", "items/\(enc(seriesId))/played", body: body, route: route)
        guard (200...299).contains(status) else { throw failure(status, data, route) }
    }

    /// Takes a movie or episode out of Continue Watching and Up Next without marking it watched.
    /// For an episode its whole show goes, until something of it plays again. The resume point is kept.
    public func removeFromContinue(_ itemId: String) async throws {
        let route = "home/continue/{id}"
        let (status, data) = try await raw("DELETE", "home/continue/\(enc(itemId))", route: route)
        guard (200...299).contains(status) else { throw failure(status, data, route) }
    }

    /// Puts a movie or show on the profile's Watchlist, or takes it off.
    public func setWatchlisted(_ itemId: String, _ on: Bool) async throws {
        try await sendJSON("PUT", "items/\(enc(itemId))/watchlist", ["on": .bool(on)], route: "items/{id}/watchlist")
    }

    /// Changes only the preferences sent and answers with them all.
    @discardableResult
    public func updatePrefs(_ changes: [String: JSONValue]) async throws -> Prefs {
        let route = "me/prefs"
        let (status, data) = try await raw("PATCH", route, body: try ArcJSON.encoder.encode(changes), route: route)
        guard (200...299).contains(status) else { throw failure(status, data, route) }
        return try decode(Prefs.self, data, route)
    }

    /// A season's watched mark: the season number is sent as a whole number, which Arc requires.
    struct SeasonPlayed: Encodable {
        let played: Bool
        let seasonNumber: Int
    }

    func sendJSON(_ method: String, _ path: String, _ body: [String: JSONValue], route: String) async throws {
        let (status, data) = try await raw(method, path, body: try ArcJSON.encoder.encode(body), route: route)
        guard (200...299).contains(status) else { throw failure(status, data, route) }
    }
}
