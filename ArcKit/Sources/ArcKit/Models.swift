import Foundation

// The parts of Arc's /api/v1 answers this app uses (docs/API.md). Everything else is ignored, as
// the v1 promise asks. Field names arrive in snake_case and are read with
// `.convertFromSnakeCase` (see ArcJSON).

public struct Health: Codable, Sendable {
    @Default<Defaults.Empty> public var name: String
    @Default<Defaults.Empty> public var version: String
    @Default<Defaults.Zero> public var apiVersion: Int
}

public struct LinkStart: Codable, Sendable {
    public let code: String
    public let poll: String
}

struct TokenAnswer: Codable, Sendable { let token: String }

public struct Profile: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    @Default<ProfileColor> public var color: String
    @Default<Defaults.False> public var hasPin: Bool
    @Default<Defaults.False> public var isAdmin: Bool

    public init(id: String, name: String, color: String = "violet", hasPin: Bool = false, isAdmin: Bool = false) {
        self.id = id
        self.name = name
        self.color = color
        self.hasPin = hasPin
        self.isAdmin = isAdmin
    }

    public enum ProfileColor: DefaultValue { public static var defaultValue: String { "violet" } }
}

public struct AuthStatus: Codable, Sendable {
    @Default<Defaults.False> public var signedIn: Bool
    public var profile: Profile?
    @Default<Defaults.List<Profile>> public var profiles: [Profile]
}

public struct Library: Codable, Sendable, Hashable, Identifiable {
    public let id: Int64
    public let name: String
    /// movies, shows or videos (Other videos).
    public let kind: String

    public init(id: Int64, name: String, kind: String) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

public struct UserData: Codable, Sendable, Hashable {
    @Default<Defaults.Zero64> public var positionMs: Int64
    @Default<Defaults.False> public var played: Bool
    @Default<Defaults.False> public var watchlisted: Bool
}

public struct Images: Codable, Sendable, Hashable {
    public var primary: String?
    public var backdrop: String?
    public var logo: String?
    public var seriesPrimary: String?
    public var seriesBackdrop: String?
    public var seriesLogo: String?
    public var seasonPrimary: String?

    public init(primary: String? = nil, backdrop: String? = nil, logo: String? = nil, seriesPrimary: String? = nil,
                seriesBackdrop: String? = nil, seriesLogo: String? = nil, seasonPrimary: String? = nil) {
        self.primary = primary
        self.backdrop = backdrop
        self.logo = logo
        self.seriesPrimary = seriesPrimary
        self.seriesBackdrop = seriesBackdrop
        self.seriesLogo = seriesLogo
        self.seasonPrimary = seasonPrimary
    }
}

public struct MediaFile: Codable, Sendable, Hashable, Identifiable {
    public let id: Int64
    @Default<Defaults.Zero64> public var durationMs: Int64
    @Default<Defaults.False> public var missing: Bool
    public var edition: String?
}

public struct Item: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    /// movie, series or episode.
    public let kind: String
    public let title: String
    public var year: Int?
    public var overview: String?
    public var tagline: String?
    public var runtimeMin: Int?
    public var contentRating: String?
    @Default<Defaults.List<String>> public var genres: [String]
    public var seriesTitle: String?
    public var seasonNumber: Int?
    public var episodeNumber: Int?
    public var userData: UserData?
    public var unwatchedCount: Int?
    public var images: Images?
    @Default<Defaults.List<MediaFile>> public var files: [MediaFile]
    /// On episodes in a season list: whether a file is on disk.
    @Default<Defaults.True> public var available: Bool

    public init(id: String, kind: String, title: String, images: Images? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.images = images
    }

    public var isEpisode: Bool { kind == "episode" }
    public var isSeries: Bool { kind == "series" }
    public var playable: Bool { kind == "movie" || kind == "episode" }

    /// How long it runs, as well as Arc knows: the file's length, or the listed runtime.
    public var durationMs: Int64 {
        files.first { !$0.missing && $0.durationMs > 0 }?.durationMs ?? Int64(runtimeMin ?? 0) * 60_000
    }

    /// A resume point, if the profile is part-way through.
    public var resumeMs: Int64 { userData.map { $0.played ? 0 : $0.positionMs } ?? 0 }

    public var watched: Bool { isSeries ? unwatchedCount == 0 : userData?.played == true }
}

public struct ItemPage: Codable, Sendable {
    @Default<Defaults.Zero> public var total: Int
    @Default<Defaults.List<Item>> public var items: [Item]
}

/// A TV library's Recently Added card: a new show, new episodes of a season, or one episode.
public struct RecentCard: Codable, Sendable {
    /// series, season or episode.
    public let type: String
    public let item: Item
    public var seasonNumber: Int?
    @Default<Defaults.Zero> public var episodes: Int
    public var seasonPoster: String?
}

public struct HomeRowPref: Codable, Sendable, Hashable {
    public let id: String
    @Default<Defaults.False> public var hidden: Bool
    public var title: String?
    /// A custom row's browse filter: passed to /items as it is.
    public var filter: [String: JSONValue]?
    public var style: String?
    @Default<Defaults.False> public var showsOnly: Bool
    /// "series" or "season": whose posters an episode row shows.
    public var posters: String?

    public init(id: String, hidden: Bool = false, title: String? = nil, filter: [String: JSONValue]? = nil, style: String? = nil) {
        self.id = id
        self.hidden = hidden
        self.title = title
        self.filter = filter
        self.style = style
    }
}

public struct SubtitleStyle: Codable, Sendable, Hashable {
    /// small, medium, large or huge; "" for the default.
    @Default<Defaults.Empty> public var size: String
    /// white or yellow.
    @Default<Defaults.Empty> public var color: String
    /// box (the default), solid or none.
    @Default<Defaults.Empty> public var background: String
    /// bottom or top.
    @Default<Defaults.Empty> public var position: String

    public init() {}
}

public struct Prefs: Codable, Sendable {
    @Default<Defaults.List<HomeRowPref>> public var home: [HomeRowPref]
    @Default<Defaults.False> public var splitUpNext: Bool
    @Default<Defaults.List<Int64>> public var libraryOrder: [Int64]
    /// How many libraries come before the Watchlist (in the sidebar and on Home).
    @Default<Defaults.Zero> public var watchlistPosition: Int
    @Default<Defaults.Empty> public var subtitleLanguage: String
    /// "" (the language last chosen), "manual", "foreign" or "always", as Plex's.
    @Default<Defaults.Empty> public var subtitleMode: String
    @Default<Defaults.Empty> public var audioLanguage: String
    @Default<Defaults.True> public var autoPlay: Bool
    public var subtitleStyle: SubtitleStyle?

    public init(home: [HomeRowPref] = [], splitUpNext: Bool = false, libraryOrder: [Int64] = [], watchlistPosition: Int = 0) {
        self.home = home
        self.splitUpNext = splitUpNext
        self.libraryOrder = libraryOrder
        self.watchlistPosition = watchlistPosition
    }
}

public struct CollectionRef: Codable, Sendable, Hashable {
    public let id: String
    public let title: String
}

public struct CollectionPage: Codable, Sendable {
    public let collection: CollectionRef
    @Default<Defaults.List<Item>> public var items: [Item]
}

public struct PlaylistEntry: Codable, Sendable {
    public let entryId: Int64
    public let item: Item
}

public struct PlaylistPage: Codable, Sendable {
    @Default<Defaults.List<PlaylistEntry>> public var entries: [PlaylistEntry]
}

/// What the player can play, as Arc's playback decision expects it (internal/api/playback.go).
public struct PlayerCaps: Codable, Sendable, Hashable {
    public var containers: [String]
    public var video: [String]
    /// Sound formats the device decodes (or passes through) in any stream.
    public var audio: [String]
    public var maxHeight: Int
    /// Sound formats the receiver takes as they are: direct play only.
    public var audioPassthrough: [String]
    /// HDR the screen shows (hdr10, hlg, hdr10_plus, dolby_vision); nil when unknown.
    public var hdrFormats: [String]?
    /// Dolby Vision profiles the decoder plays; nil when unknown.
    public var dolbyVisionProfiles: [Int]?

    public init(containers: [String], video: [String], audio: [String], maxHeight: Int, audioPassthrough: [String] = [],
                hdrFormats: [String]? = nil, dolbyVisionProfiles: [Int]? = nil) {
        self.containers = containers
        self.video = video
        self.audio = audio
        self.maxHeight = maxHeight
        self.audioPassthrough = audioPassthrough
        self.hdrFormats = hdrFormats
        self.dolbyVisionProfiles = dolbyVisionProfiles
    }

    /// Caps for trying again after the player failed (web/src/lib/playback.ts): a file played as
    /// it is failed, so have it repackaged; repackaged failed, so have the video converted too.
    public func fallback(after failedMethod: String) -> PlayerCaps {
        var caps = self
        caps.containers = []
        if failedMethod != "direct" { caps.video = [] }
        return caps
    }
}

public struct PlaybackRequest: Codable, Sendable {
    public var caps: PlayerCaps
    public var startMs: Int64
    public var fileId: Int64?
    public var audioStream: Int?

    public init(caps: PlayerCaps, startMs: Int64 = 0, fileId: Int64? = nil, audioStream: Int? = nil) {
        self.caps = caps
        self.startMs = startMs
        self.fileId = fileId
        self.audioStream = audioStream
    }
}

public struct AudioTrack: Codable, Sendable, Hashable, Identifiable {
    public let index: Int
    public var language: String?
    public var title: String?
    @Default<Defaults.Empty> public var codec: String
    @Default<Defaults.Zero> public var channels: Int
    public var id: Int { index }
}

public struct SubtitleTrack: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public var language: String?
    public var title: String?
    @Default<Defaults.Empty> public var codec: String
    @Default<Defaults.False> public var forced: Bool
    /// A picture format (Blu-ray, DVD): Arc can only burn these in.
    @Default<Defaults.False> public var image: Bool
}

public struct Marker: Codable, Sendable, Hashable {
    /// intro, recap or credits.
    public let kind: String
    public let startMs: Int64
    public let endMs: Int64
}

public struct PlaybackPlan: Codable, Sendable {
    /// direct, remux or transcode.
    public let method: String
    @Default<Defaults.List<String>> public var reasons: [String]
    public let url: String
    @Default<Defaults.False> public var hls: Bool
    public var sessionId: String?
    /// Where a converted stream starts in the file: add it to the player's clock.
    @Default<Defaults.Zero64> public var offsetMs: Int64
    @Default<Defaults.Zero64> public var durationMs: Int64
    @Default<Defaults.Zero64> public var fileId: Int64
    @Default<Defaults.MinusOne> public var audioStream: Int
    @Default<Defaults.List<AudioTrack>> public var audioTracks: [AudioTrack]
    @Default<Defaults.List<SubtitleTrack>> public var subtitleTracks: [SubtitleTrack]
    @Default<Defaults.List<Marker>> public var markers: [Marker]

    public init(method: String, url: String, hls: Bool = false, sessionId: String? = nil, offsetMs: Int64 = 0, durationMs: Int64 = 0) {
        self.method = method
        self.url = url
        self.hls = hls
        self.sessionId = sessionId
        self.offsetMs = offsetMs
        self.durationMs = durationMs
    }
}

public struct ProgressReport: Codable, Sendable {
    public let positionMs: Int64
    public let durationMs: Int64
    /// playing, paused or stopped.
    public let state: String

    public init(positionMs: Int64, durationMs: Int64, state: String) {
        self.positionMs = positionMs
        self.durationMs = durationMs
        self.state = state
    }
}

/// This server's own identity (GET /identity): its friendly name, set in Arc's settings.
public struct Identity: Codable, Sendable {
    @Default<Defaults.Empty> public var name: String
}

struct CastAnswer: Codable, Sendable { let url: String }

public struct Season: Codable, Sendable, Hashable, Identifiable {
    public let seasonNumber: Int
    @Default<Defaults.Empty> public var name: String
    public var poster: String?
    @Default<Defaults.List<Item>> public var episodes: [Item]
    public var id: Int { seasonNumber }
}

/// GET /series/{id}/seasons: a show's seasons in the profile's ordering, with their episodes.
public struct SeasonsResponse: Codable, Sendable {
    public let series: Item
    @Default<Defaults.List<Season>> public var seasons: [Season]
}
