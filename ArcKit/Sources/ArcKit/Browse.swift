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
    /// What the files are (arc-media-server FILTER-DISCOVERY-API.md): lower-case ffprobe names,
    /// channel counts as strings ("6" is 5.1), and dolby_vision, hdr10_plus, hlg, hdr10, sdr or unknown.
    @Default<Defaults.List<FacetValue>> public var videoCodecs: [FacetValue]
    @Default<Defaults.List<FacetValue>> public var audioCodecs: [FacetValue]
    @Default<Defaults.List<FacetValue>> public var audioChannels: [FacetValue]
    @Default<Defaults.List<FacetValue>> public var dynamicRanges: [FacetValue]

    /// The choices a media filter offers, as the web's `offered`: none when the library has only
    /// one value (nothing to narrow), unless one is already chosen; a chosen value the library no
    /// longer has stays listed, so it can be seen and changed.
    public static func offered(_ values: [FacetValue], chosen: String?) -> [String] {
        var out = values.map(\.value)
        if let chosen, !out.contains(chosen) { out.append(chosen) }
        return out.count > 1 || chosen != nil ? out : []
    }
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
    /// A smart playlist's rules: it fills itself, so titles can't be added to it.
    public var smartFilter: JSONValue?

    /// Titles can be added to it (not a smart playlist).
    public var editable: Bool {
        switch smartFilter {
        case nil, .null?: return true
        default: return false
        }
    }
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
    /// Watched or Not Started (`played` / `unstarted`); excludes Unwatched Only, as Arc requires.
    public private(set) var watchState: String?
    public var dynamicRange: String?
    public var videoCodec: String?
    public var audioCodec: String?
    /// A channel count, as a string ("6" is 5.1).
    public var audioChannels: String?

    public init() {}

    /// Unwatched Only on or off; on turns Watch Status off (Arc refuses both).
    public mutating func setUnwatched(_ on: Bool) {
        unwatchedOnly = on
        if on { watchState = nil }
    }

    /// Watch Status (`played`, `unstarted`, or nil for any); a choice turns Unwatched Only off.
    public mutating func setWatchState(_ state: String?) {
        watchState = state
        if state != nil { unwatchedOnly = false }
    }

    /// Every filter off; the sort stays.
    public var cleared: LibraryQuery {
        var q = LibraryQuery()
        q.sort = sort
        q.reversed = reversed
        return q
    }

    /// The /items parameters for `library`'s grid, `limit` titles from `offset`. `letters` asks
    /// for the A–Z bar's counts too (only sorted by title, where letters mean something).
    public func parameters(library: Library, offset: Int, limit: Int, letters: Bool = false) -> [String: String] {
        var p = ["library_id": String(library.id), "kind": library.kind == "shows" ? "series" : "movie",
                 "sort": sort.rawValue, "offset": String(offset), "limit": String(limit)]
        if letters && showsLetters { p["letters"] = "1" }
        if reversed { p["reverse"] = "1" }
        if unwatchedOnly { p["unwatched"] = "1" }
        if let genre { p["genre"] = genre }
        if let decade { p["decade"] = decade }
        if let resolution { p["resolution"] = resolution }
        if let watchState { p["watch_state"] = watchState }
        if let dynamicRange { p["dynamic_range"] = dynamicRange }
        if let videoCodec { p["video_codec"] = videoCodec }
        if let audioCodec { p["audio_codec"] = audioCodec }
        if let audioChannels { p["audio_channels"] = audioChannels }
        return p
    }

    /// The filters chosen, for the Filters button's name and Clear Filters.
    public var filterCount: Int {
        [unwatchedOnly ? "1" : nil, genre, decade, resolution, watchState, dynamicRange, videoCodec, audioCodec, audioChannels]
            .compactMap { $0 }.count
    }

    public var filtered: Bool { filterCount > 0 }

    /// The A–Z bar is offered with the title sort only, as on the web and Android.
    public var showsLetters: Bool { sort == .title }
}

/// How many titles in a listing start with one character of their sort title (GET /items with
/// letters=1): "a" to "z", or "#" for anything else. They come in title order, so "#" can come
/// twice: before "a" for digits and punctuation, after "z" for other scripts.
public struct LetterCount: Codable, Sendable, Hashable {
    public let letter: String
    @Default<Defaults.Zero> public var count: Int

    public init(letter: String, count: Int) {
        self.letter = letter
        self.count = count
    }
}

/// A place on the A–Z bar: the letter as shown ("A", or "#") and where its first title is in the list.
public struct LetterJump: Sendable, Hashable, Identifiable {
    public let letter: String
    public let offset: Int
    public var id: String { letter }
}

/// Where each letter's first title is in a title-sorted list, in the list's own order (the web's
/// and Android's letterOffsets): Z to A when the sort is reversed. Letters with no titles are left
/// out, and a "#" that comes twice keeps its first place.
public func letterJumps(_ letters: [LetterCount], reversed: Bool) -> [LetterJump] {
    var out: [LetterJump] = []
    var seen: Set<String> = []
    var at = 0
    for l in reversed ? letters.reversed() : letters {
        let letter = l.letter.count == 1 && l.letter.lowercased() >= "a" && l.letter.lowercased() <= "z" ? l.letter.uppercased() : "#"
        if l.count > 0, seen.insert(letter).inserted { out.append(LetterJump(letter: letter, offset: at)) }
        at += l.count
    }
    return out
}

/// The requests that load a grid from the `have` titles it holds through `target` and a page
/// past it, so a jump to a letter lands on a full screen of titles: (offset, limit) pairs, at most
/// `maxLimit` each (/items takes up to 500).
public func pagesToReach(_ target: Int, have: Int, total: Int, page: Int, maxLimit: Int = 500) -> [(offset: Int, limit: Int)] {
    let end = min(total, target + page)
    var out: [(offset: Int, limit: Int)] = []
    var at = have
    while at < end {
        let limit = min(maxLimit, end - at)
        out.append((at, limit))
        at += limit
    }
    return out
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

    /// The profile's own rating of a movie, show or episode: 1–10 (half stars out of five), or 0
    /// to clear it.
    public func setRating(_ itemId: String, _ rating: Int) async throws {
        try await sendJSON("PUT", "items/\(enc(itemId))/rating", ["rating": .number(Double(min(max(rating, 0), 10)))], route: "items/{id}/rating")
    }

    /// Adds titles (movies, episodes or whole shows) to the end of a playlist; answers with how
    /// many were added.
    @discardableResult
    public func addToPlaylist(_ playlistId: String, itemIds: [String]) async throws -> Int {
        let added: PlaylistAdded = try await sendJSON("POST", "playlists/\(enc(playlistId))/items", PlaylistItems(itemIds: itemIds),
                                                      route: "playlists/{id}/items")
        return added.added
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

/// A pre-roll video Arc plays before a film (Plex's cinema trailers): `url` is its /api/preroll/{n}.
public struct PrerollClip: Codable, Sendable, Hashable {
    @Default<Defaults.Empty> public var title: String
    public let url: String
}

extension ArcAPI {
    /// The pre-roll videos to play before a film, in order; none for episodes, home videos, or
    /// when none are set in Arc's Settings.
    public func preroll(_ itemId: String) async throws -> [PrerollClip] {
        try await get("items/\(enc(itemId))/preroll", route: "items/{id}/preroll")
    }
}

private struct PlaylistItems: Encodable { let itemIds: [String] }
private struct PlaylistAdded: Decodable { @Default<Defaults.Zero> var added: Int }

/// The profile's own star rating as the apps show it: Arc keeps 1–10, shown as half stars out of
/// five (the web's StarRating).
public enum StarRating {
    /// The choices, best first: 10 (five stars) down to 1 (half a star).
    public static let choices = Array((1...10).reversed())

    /// "★★★½" for 7; nil when not rated.
    public static func stars(_ rating: Int?) -> String? {
        guard let r = rating, (1...10).contains(r) else { return nil }
        return String(repeating: "★", count: r / 2) + (r % 2 == 1 ? "½" : "")
    }

    /// Stars out of five for 7: "3.5" (what VoiceOver reads after "of 5").
    public static func outOfFive(_ rating: Int) -> String {
        rating % 2 == 0 ? String(rating / 2) : String(rating / 2) + ".5"
    }
}
