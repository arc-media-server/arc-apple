import Foundation

/// What a Home row shows. Built-in rows are named by the app; custom rows keep their own title.
public enum RowSource: Sendable, Hashable {
    case continueWatching(withUpNext: Bool)
    case nextUp
    case watchlist
    case recent(Library, showsOnly: Bool)
    case custom(title: String, library: Library, filter: [String: JSONValue])
    case seasonal(SeasonalPick)
    /// A collection or playlist: `title` is the name saved with the row.
    case collection(id: String, title: String)
    case playlist(id: String, title: String)
}

/// Posters, wide thumbnails, or Backdrops (the web's "arc": background art with the logo).
public enum CardStyle: Sendable, Hashable { case poster, thumb, backdrop }

/// A Home row and its look; `seasonPosters` shows an episode's or season's own poster rather than its show's.
public struct HomeRowSpec: Sendable, Hashable, Identifiable {
    public let id: String
    public let source: RowSource
    public let style: CardStyle
    public var seasonPosters = false
}

/// The seasonal row's picks and their dates (web/src/lib/home.ts seasons): films for the time of
/// year, across the libraries, shuffled daily.
public enum SeasonalPick: String, Sendable, Hashable, CaseIterable {
    case romance, horror, christmas

    var dates: (from: Int, to: Int) {
        switch self {
        case .romance: return (201, 214)
        case .horror: return (1001, 1031)
        case .christmas: return (1201, 1231)
        }
    }

    public var query: [String: String] {
        switch self {
        case .romance: return ["kind": "movie", "genre": "Romance", "sort": "shuffle"]
        case .horror: return ["kind": "movie", "genre": "Horror", "sort": "shuffle"]
        case .christmas: return ["kind": "movie", "about": "christmas,santa,xmas,north pole,reindeer,elves", "sort": "shuffle"]
        }
    }

    /// The pick for a date, or nil outside every season.
    public static func on(_ date: Date, calendar: Calendar = .current) -> SeasonalPick? {
        let parts = calendar.dateComponents([.month, .day], from: date)
        let md = (parts.month ?? 0) * 100 + (parts.day ?? 0)
        return allCases.first { md >= $0.dates.from && md <= $0.dates.to }
    }
}

/// The libraries in the profile's order (Arrange libraries on the web); new ones go last.
public func orderedLibraries(_ libraries: [Library], order: [Int64]) -> [Library] {
    let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
    return libraries.enumerated().sorted { a, b in
        (rank[a.element.id] ?? order.count + a.offset, a.offset) < (rank[b.element.id] ?? order.count + b.offset, b.offset)
    }.map(\.element)
}

/// A saved row look (poster, thumb or arc) as a card style; nil for automatic.
public func cardStyle(saved: String?) -> CardStyle? {
    switch saved {
    case "poster": return .poster
    case "thumb": return .thumb
    case "arc": return .backdrop
    default: return nil
    }
}

/// The profile's Home rows, as the web arranges them (web/src/lib/home.ts resolveRows; the
/// Android app's resolveHomeRows): carrying on watching first, then each library's newest and its
/// own filter rows in the profile's library order, the Watchlist at its place among them, and
/// collections and playlists last. `libraries` must be in the profile's order. Hidden rows are
/// left out. The layout is arranged on the web; the Apple TV follows it.
public func resolveHomeRows(prefs: Prefs, libraries: [Library], today: Date = Date()) -> [HomeRowSpec] {
    let saved = Dictionary(prefs.home.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    func shown(_ id: String) -> Bool { saved[id]?.hidden != true }
    var out: [HomeRowSpec] = []
    func carryOn(_ id: String, _ source: RowSource) {
        let row = saved[id]
        out.append(HomeRowSpec(id: id, source: source, style: cardStyle(saved: row?.style) ?? .thumb, seasonPosters: row?.posters == "season"))
    }
    if shown("continue") { carryOn("continue", .continueWatching(withUpNext: !prefs.splitUpNext)) }
    if prefs.splitUpNext && shown("next-up") { carryOn("next-up", .nextUp) }
    if let pick = SeasonalPick.on(today), shown("seasonal") {
        out.append(HomeRowSpec(id: "seasonal", source: .seasonal(pick), style: .poster))
    }
    let watchlistAt = min(max(prefs.watchlistPosition, 0), libraries.count)
    for (i, lib) in libraries.enumerated() {
        if i == watchlistAt && shown("watchlist") { out.append(HomeRowSpec(id: "watchlist", source: .watchlist, style: .poster)) }
        // Home videos rarely have posters worth showing: their rows use thumbnails.
        let look: CardStyle = lib.kind == "videos" ? .thumb : .poster
        let recent = "recent:\(lib.id)"
        if shown(recent) {
            out.append(HomeRowSpec(id: recent, source: .recent(lib, showsOnly: saved[recent]?.showsOnly == true), style: look, seasonPosters: true))
        }
        for row in prefs.home where row.id.hasPrefix("custom:") && !row.hidden {
            guard let filter = row.filter, let title = row.title, !title.trimmingCharacters(in: .whitespaces).isEmpty,
                  filter["library_id"]?.queryValue == String(lib.id) else { continue }
            out.append(HomeRowSpec(id: row.id, source: .custom(title: title, library: lib, filter: filter), style: look))
        }
    }
    if watchlistAt == libraries.count && shown("watchlist") { out.append(HomeRowSpec(id: "watchlist", source: .watchlist, style: .poster)) }
    // Collections and playlists come last, in the order they were added (no library to follow).
    for row in prefs.home where !row.hidden {
        if row.id.hasPrefix("collection:") {
            out.append(HomeRowSpec(id: row.id, source: .collection(id: String(row.id.dropFirst("collection:".count)), title: row.title ?? ""), style: .poster))
        } else if row.id.hasPrefix("playlist:") {
            out.append(HomeRowSpec(id: row.id, source: .playlist(id: String(row.id.dropFirst("playlist:".count)), title: row.title ?? ""), style: .poster))
        }
    }
    return out
}

/// /items query parameters for a custom row's filter (web/src/lib/home.ts rowQuery).
public func customRowQuery(filter: [String: JSONValue], library: Library, limit: Int = 24) -> [String: String] {
    let keys = ["library_id", "genre", "language", "label", "decade", "resolution", "unwatched", "added_within",
                "min_runtime", "max_runtime", "min_rating", "sort"]
    var out: [String: String] = [:]
    for k in keys {
        guard let v = filter[k]?.queryValue, !v.isEmpty, v != "0" else { continue }
        out[k] = v
    }
    out["kind"] = library.kind == "shows" ? "series" : "movie"
    out["limit"] = String(limit)
    return out
}

/// /items query parameters for a library's titles in an order.
public func libraryQuery(_ library: Library, sort: String, limit: Int) -> [String: String] {
    ["library_id": String(library.id), "kind": library.kind == "shows" ? "series" : "movie", "sort": sort, "limit": String(limit)]
}

/// A card on a row: a title, or a season of a show with new episodes.
public struct MediaCard: Sendable, Hashable, Identifiable {
    public let id: String
    public let item: Item
    /// A season of new episodes (Recently Added in a TV library): its number and how many.
    public var seasonNumber: Int?
    public var newEpisodes = 0
    public var poster: String?
    /// The episode's season poster, or a new season's own.
    public var seasonPoster: String?
    public var thumb: String?
    public var backdrop: String?
    public var logo: String?
    /// How far through, 0–1, or nil when not started.
    public var progress: Double?

    /// An item as a card, choosing artwork as the web's PosterCard and EpisodeCard do.
    public init(item: Item, id: String? = nil) {
        let img = item.images
        self.id = id ?? item.id
        self.item = item
        poster = item.isEpisode ? img?.seriesPrimary ?? img?.primary : img?.primary
        seasonPoster = item.isEpisode ? img?.seasonPrimary : nil
        thumb = item.isEpisode ? img?.primary ?? img?.seriesBackdrop ?? img?.backdrop : img?.backdrop ?? img?.primary
        backdrop = item.isEpisode ? img?.seriesBackdrop ?? img?.primary : img?.backdrop ?? img?.primary
        logo = item.isEpisode ? img?.seriesLogo : img?.logo
        let duration = item.durationMs
        progress = item.resumeMs > 0 && duration > 0 ? min(1, max(0.02, Double(item.resumeMs) / Double(duration))) : nil
    }

    /// A TV library's Recently Added card.
    public init(recent: RecentCard) {
        self.init(item: recent.item, id: "\(recent.type):\(recent.item.id):\(recent.seasonNumber.map(String.init) ?? "")")
        if recent.type == "season" {
            seasonNumber = recent.seasonNumber
            newEpisodes = recent.episodes
            seasonPoster = recent.seasonPoster ?? poster
        }
    }

    /// The picture a card of `style` shows.
    public func art(_ style: CardStyle, seasonPosters: Bool) -> String? {
        switch style {
        case .poster: return seasonPosters ? seasonPoster ?? poster : poster
        case .thumb: return thumb
        case .backdrop: return backdrop
        }
    }
}
