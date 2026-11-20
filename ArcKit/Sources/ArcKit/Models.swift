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
    /// Whether the server sees this device on its local network.
    public var local: Bool?
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
    /// The profile's own rating: 1–10, half stars out of five (nil or 0: not rated).
    public var rating: Int?
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
    public var container: String?
    public var size: Int64?
    public var bitrate: Int64?
    /// Where the file is on the server (the title page's Playback card shows its name).
    public var path: String?
    /// The file's video, audio and subtitle tracks as ffprobe read them (a title's page).
    @Default<Defaults.List<MediaStream>> public var streams: [MediaStream]
}

/// One track of a file: what the title page's quality badges and Playback card are made from.
public struct MediaStream: Codable, Sendable, Hashable {
    /// video, audio or subtitle.
    @Default<Defaults.Empty> public var kind: String
    @Default<Defaults.Empty> public var codec: String
    public var profile: String?
    public var width: Int?
    public var height: Int?
    public var channels: Int?
    public var language: String?
    public var colorTransfer: String?
    @Default<Defaults.False> public var dolbyVision: Bool
    public var dolbyVisionProfile: Int?
    /// Frames a second (23.976, 25, 50…), for the TV's frame-rate matching.
    public var frameRate: Double?
    @Default<Defaults.False> public var hdr10Plus: Bool
    @Default<Defaults.False> public var isDefault: Bool

    public init(kind: String, codec: String, profile: String? = nil, width: Int? = nil, height: Int? = nil, channels: Int? = nil,
                colorTransfer: String? = nil, dolbyVision: Bool = false, hdr10Plus: Bool = false, isDefault: Bool = false) {
        self.kind = kind
        self.codec = codec
        self.profile = profile
        self.width = width
        self.height = height
        self.channels = channels
        self.colorTransfer = colorTransfer
        self.dolbyVision = dolbyVision
        self.hdr10Plus = hdr10Plus
        self.isDefault = isDefault
    }
}

public struct Item: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    /// movie, series or episode.
    public let kind: String
    public let title: String
    public var year: Int?
    public var overview: String?
    public var tagline: String?
    /// The title's theme tune (`items/{id}/theme`), for films and shows that have one.
    public var themeUrl: String?
    public var runtimeMin: Int?
    public var contentRating: String?
    @Default<Defaults.List<String>> public var genres: [String]
    /// A title's page: where it's from and when it came out.
    public var studio: String?
    public var releaseDate: String?
    public var originalTitle: String?
    public var originalLanguage: String?
    public var seriesTitle: String?
    public var seasonNumber: Int?
    public var episodeNumber: Int?
    public var userData: UserData?
    public var unwatchedCount: Int?
    public var images: Images?
    @Default<Defaults.List<MediaFile>> public var files: [MediaFile]
    /// On episodes in a season list: whether a file is on disk.
    @Default<Defaults.True> public var available: Bool
    /// On a title's own page (items/{id}): its cast and crew, and the collections it's in.
    @Default<Defaults.List<Credit>> public var credits: [Credit]
    @Default<Defaults.List<CollectionRef>> public var collections: [CollectionRef]
    /// An episode's show.
    public var parentId: String?
    /// Trailers and other extras (a title's page).
    @Default<Defaults.List<Extra>> public var extras: [Extra]

    public init(id: String, kind: String, title: String, images: Images? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.images = images
    }

    public var isEpisode: Bool { kind == "episode" }
    /// An episode with a place in its show's order, so "S1 · E4" means something. Arc sends season
    /// 0 and episode 0 for one the order doesn't place ("Not in This Order"); specials keep theirs
    /// (season 0, episode 1 and on).
    public var hasEpisodeCode: Bool { isEpisode && ((seasonNumber ?? 0) != 0 || (episodeNumber ?? 0) != 0) }
    public var isSeries: Bool { kind == "series" }
    public var playable: Bool { kind == "movie" || kind == "episode" }

    /// How long it runs, as well as Arc knows: the file's length, or the listed runtime.
    public var durationMs: Int64 {
        files.first { !$0.missing && $0.durationMs > 0 }?.durationMs ?? Int64(runtimeMin ?? 0) * 60_000
    }

    /// A resume point, if the profile is part-way through.
    public var resumeMs: Int64 { userData.map { $0.played ? 0 : $0.positionMs } ?? 0 }

    public var watched: Bool { isSeries ? unwatchedCount == 0 : userData?.played == true }

    /// How an upcoming release reads on its card: the weekday within the next six days
    /// ("Thursday"), else the day and month ("19 Nov"), in the viewer's language.
    public static func releaseDay(_ day: Date, asOf today: Date = Date(), calendar: Calendar = .current,
                                  locale: Locale = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: calendar.startOfDay(for: day)).day ?? 99
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate(days >= 1 && days <= 6 ? "EEEE" : "d MMM")
        return f.string(from: day)
    }

    /// The day an episode not yet on the server airs, when that's after `today` ("Releases
    /// 8 Nov" on its card); nil once it's out or when Arc has its file.
    public func upcomingRelease(asOf today: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard !available, let iso = releaseDate else { return nil }
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let day = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return nil }
        return day > calendar.startOfDay(for: today) ? day : nil
    }
}

public struct ItemPage: Codable, Sendable {
    @Default<Defaults.Zero> public var total: Int
    @Default<Defaults.List<Item>> public var items: [Item]
    /// With letters=1: the titles counted by their first letter, for the A–Z bar.
    @Default<Defaults.List<LetterCount>> public var letters: [LetterCount]
}

/// A TV library's Recently Added card: a new show, new episodes of a season, or one episode.
public struct RecentCard: Codable, Sendable {
    /// series, season or episode.
    public let type: String
    public let item: Item
    public var seasonNumber: Int?
    @Default<Defaults.Zero> public var episodes: Int
    public var seasonPoster: String?
    /// When the card's newest episode was added (Unix seconds). The same show or season can
    /// appear more than once, one card per day's batch, so this is part of its identity.
    @Default<Defaults.Zero64> public var addedAt: Int64
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
    /// Skip intros and recaps without pressing Skip.
    @Default<Defaults.False> public var autoSkip: Bool
    /// Play a film's or show's theme tune quietly on its page (on unless turned off).
    @Default<Defaults.True> public var themeMusic: Bool
    /// Hide Spoilers: unwatched episodes' stills and descriptions stay back.
    @Default<Defaults.False> public var hideSpoilers: Bool
    public var subtitleStyle: SubtitleStyle?

    public init(home: [HomeRowPref] = [], splitUpNext: Bool = false, libraryOrder: [Int64] = [], watchlistPosition: Int = 0) {
        self.home = home
        self.splitUpNext = splitUpNext
        self.libraryOrder = libraryOrder
        self.watchlistPosition = watchlistPosition
    }
}

public struct CollectionRef: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    /// On a collection's own page (collections/{id}).
    public var overview: String?
    public var images: Images?
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
    /// The deepest colour (bits) the decoder plays; nil for the server's default (8-bit H.264).
    public var maxBitDepth: Int?
    /// The most sound channels the output takes (2 for stereo, 6 for 5.1, 8 for 7.1); nil when
    /// unknown, which leaves the sound as it is.
    public var maxAudioChannels: Int?

    public init(containers: [String], video: [String], audio: [String], maxHeight: Int, audioPassthrough: [String] = [],
                hdrFormats: [String]? = nil, dolbyVisionProfiles: [Int]? = nil, maxBitDepth: Int? = nil, maxAudioChannels: Int? = nil) {
        self.maxBitDepth = maxBitDepth
        self.maxAudioChannels = maxAudioChannels
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
    /// A quality limit (kbit/s); nil for the original.
    public var maxKbps: Int?
    /// A picture subtitle track to draw into the picture (Arc converts the video to do it).
    public var burnSubtitle: String?

    public init(caps: PlayerCaps, startMs: Int64 = 0, fileId: Int64? = nil, audioStream: Int? = nil, burnSubtitle: String? = nil, maxKbps: Int? = nil) {
        self.caps = caps
        self.maxKbps = maxKbps
        self.startMs = startMs
        self.fileId = fileId
        self.audioStream = audioStream
        self.burnSubtitle = burnSubtitle
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
    @Default<Defaults.False> public var hearingImpaired: Bool

    public init(id: String, language: String? = nil, title: String? = nil, forced: Bool = false, image: Bool = false, hearingImpaired: Bool = false) {
        self.id = id
        self.language = language
        self.title = title
        self.forced = forced
        self.image = image
        self.hearingImpaired = hearingImpaired
    }
}

public struct Marker: Codable, Sendable, Hashable {
    /// intro, recap or credits.
    public let kind: String
    public let startMs: Int64
    public let endMs: Int64

    public init(kind: String, startMs: Int64, endMs: Int64) {
        self.kind = kind
        self.startMs = startMs
        self.endMs = endMs
    }
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
    /// The title's files to choose from (editions, versions).
    @Default<Defaults.List<Version>> public var versions: [Version]
    @Default<Defaults.List<Chapter>> public var chapters: [Chapter]
    /// The file's overall bitrate (kbit/s), so only lower qualities are offered.
    @Default<Defaults.Zero> public var sourceKbps: Int
    @Default<Defaults.Zero> public var sourceHeight: Int
    /// Away from home, the most the server allows (0 at home).
    @Default<Defaults.Zero> public var serverLimitKbps: Int

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

    /// The number of the "Not in This Order" tab, which no real season has.
    public static let unplacedNumber = -1
    /// The episodes the order doesn't place, as a tab after the seasons (`SeasonsResponse.tabs`).
    public var isUnplaced: Bool { seasonNumber == Self.unplacedNumber }

    public init(seasonNumber: Int, name: String = "", poster: String? = nil, episodes: [Item] = []) {
        self.seasonNumber = seasonNumber
        self.name = name
        self.poster = poster
        self.episodes = episodes
    }

    /// Every episode that can be played is watched (episodes not out yet don't count). A season
    /// with nothing to play isn't watched.
    public var watched: Bool {
        let playable = episodes.filter(\.available)
        return !playable.isEmpty && playable.allSatisfy(\.watched)
    }

    /// Whether the season has anything to mark watched or unwatched. Not in This Order isn't a
    /// season Arc can mark (it has no season number), so it never is.
    public var markable: Bool { !isUnplaced && episodes.contains(where: \.available) }
}

/// GET /series/{id}/seasons: a show's seasons in the profile's ordering, with their episodes.
public struct SeasonsResponse: Codable, Sendable {
    public let series: Item
    @Default<Defaults.List<Season>> public var seasons: [Season]
    /// Episodes the profile has that this order doesn't place. They're shown, never hidden
    /// (nothing silently disappears), but have no number in it, and Play and Up Next don't reach them.
    @Default<Defaults.List<Item>> public var unplaced: [Item]

    /// The show's tabs: the order's seasons, then "Not in This Order" (named `unplacedName`) when
    /// it has such episodes, as the web's show page and the Roku app have them.
    public func tabs(unplacedName: String) -> [Season] {
        unplaced.isEmpty ? seasons : seasons + [Season(seasonNumber: Season.unplacedNumber, name: unplacedName, episodes: unplaced)]
    }

    /// The tab an episode is in, with only the episodes that can be played: the player's Episodes
    /// card. Nil when the episode isn't in any.
    public func tab(containing episodeId: String) -> Season? {
        guard let tab = tabs(unplacedName: "").first(where: { $0.episodes.contains { $0.id == episodeId } }) else { return nil }
        return Season(seasonNumber: tab.seasonNumber, name: tab.name, poster: tab.poster, episodes: tab.episodes.filter(\.available))
    }
}
