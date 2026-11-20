import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// The player's choices, as the web player makes them (web/src/lib/playback.ts): which subtitles
// turn on, what the profile remembers, which marker is on screen, and what plays next.

/// A line of subtitles, in the file's time.
public struct SubtitleCue: Codable, Sendable, Hashable {
    public let startMs: Int64
    public let endMs: Int64
    /// Line breaks kept; only <i>, <b> and <u> tags.
    public let text: String

    public init(startMs: Int64, endMs: Int64, text: String) {
        self.startMs = startMs
        self.endMs = endMs
        self.text = text
    }
}

public struct SubtitleCues: Codable, Sendable {
    @Default<Defaults.List<SubtitleCue>> public var cues: [SubtitleCue]
}

/// Whether two language codes name the same language ("en", "eng" and "en-GB" do).
public func sameLanguage(_ a: String?, _ b: String?) -> Bool {
    guard let a = baseLanguage(a), let b = baseLanguage(b) else { return false }
    return a == b
}

private let alpha3: [String: String] = [
    "eng": "en", "fre": "fr", "fra": "fr", "ger": "de", "deu": "de", "spa": "es", "ita": "it", "por": "pt",
    "dut": "nl", "nld": "nl", "swe": "sv", "nor": "no", "nob": "no", "dan": "da", "fin": "fi", "pol": "pl",
    "rus": "ru", "jpn": "ja", "kor": "ko", "chi": "zh", "zho": "zh", "ara": "ar", "heb": "he", "hin": "hi",
    "tur": "tr", "gre": "el", "ell": "el", "cze": "cs", "ces": "cs", "hun": "hu", "rum": "ro", "ron": "ro",
    "ukr": "uk", "tha": "th", "vie": "vi", "ind": "id", "may": "ms", "msa": "ms", "bul": "bg", "hrv": "hr",
    "srp": "sr", "slv": "sl", "slo": "sk", "slk": "sk", "ice": "is", "isl": "is", "cat": "ca", "baq": "eu",
    "eus": "eu", "glg": "gl", "per": "fa", "fas": "fa", "est": "et", "lav": "lv", "lit": "lt", "wel": "cy",
    "cym": "cy", "gle": "ga", "tam": "ta", "tel": "te", "ben": "bn", "urd": "ur", "fil": "tl", "tgl": "tl",
]

private func baseLanguage(_ code: String?) -> String? {
    guard var c = code?.lowercased().trimmingCharacters(in: .whitespaces), !c.isEmpty, c != "und" else { return nil }
    if let dash = c.firstIndex(where: { $0 == "-" || $0 == "_" }) { c = String(c[..<dash]) }
    return alpha3[c] ?? c
}

/// The subtitles that turn on by themselves, as Plex's modes: "manual" only forced ones,
/// "foreign" the profile's language when the audio is in another, "always" its language whenever
/// there is one, "" (the default) the language last chosen. Otherwise forced subtitles in the
/// audio's language.
public func chooseSubtitle(_ tracks: [SubtitleTrack], preferred: String, audioLanguage: String?, mode: String) -> SubtitleTrack? {
    let wanted: Bool
    switch mode {
    case "manual": wanted = false
    case "foreign": wanted = !preferred.isEmpty && audioLanguage != nil && !sameLanguage(audioLanguage, preferred)
    default: wanted = true
    }
    if !preferred.isEmpty && wanted {
        let matching = tracks.filter { sameLanguage($0.language, preferred) }
        if let best = matching.first(where: { !$0.forced && !$0.hearingImpaired && !$0.image }) ?? matching.first(where: { !$0.forced }) ?? matching.first {
            return best
        }
    }
    return tracks.first { $0.forced && ($0.language == nil || audioLanguage == nil || sameLanguage($0.language, audioLanguage)) }
}

/// What a choice in the player saves as the profile's subtitle language: a track's language, or
/// "" for Off in the default mode; nil when nothing should change (forced tracks, other modes' Off).
public func rememberedSubtitleLanguage(_ track: SubtitleTrack?, mode: String) -> String? {
    if let track, !track.forced { return track.language ?? "" }
    if track == nil && mode.isEmpty { return "" }
    return nil
}

/// The cue showing at `ms`, if any. `cues` are in time order (as Arc sends them).
public func cue(at ms: Int64, in cues: [SubtitleCue]) -> SubtitleCue? {
    var lo = 0, hi = cues.count
    while lo < hi {
        let mid = (lo + hi) / 2
        if cues[mid].startMs <= ms { lo = mid + 1 } else { hi = mid }
    }
    // Cues can overlap: look back a little from the last one that started.
    var i = lo - 1
    while i >= 0 && i >= lo - 4 {
        if cues[i].endMs > ms { return cues[i] }
        i -= 1
    }
    return nil
}

/// The intro, recap or credits marker playing at `ms`, if any.
public func activeMarker(_ markers: [Marker], at ms: Int64) -> Marker? {
    markers.first { ["intro", "recap", "credits"].contains($0.kind) && ms >= $0.startMs && ms < $0.endMs - 1_000 }
}

/// When the Up Next card shows: at the credits, else in the last 30 seconds.
public func showsUpNext(markers: [Marker], positionMs: Int64, durationMs: Int64) -> Bool {
    guard durationMs > 0 else { return false }
    if let credits = markers.first(where: { $0.kind == "credits" }) {
        return positionMs >= credits.startMs
    }
    return positionMs >= durationMs - 30_000
}

extension ArcAPI {
    /// A text subtitle track's cues, read out of the file (or beside it) by Arc.
    public func subtitleCues(itemId: String, track: String, fileId: Int64) async throws -> [SubtitleCue] {
        let answer: SubtitleCues = try await get("items/\(enc(itemId))/subtitles/\(enc(track))?file=\(fileId)", route: "items/{id}/subtitles/{track}")
        return answer.cues
    }

    /// The episode that follows `itemId` in the profile's order; nil after the last (or a movie).
    public func nextEpisode(_ itemId: String) async throws -> Item? {
        let route = "items/{id}/next"
        let (status, data) = try await raw("GET", "items/\(enc(itemId))/next", route: route)
        if status == 204 { return nil }
        guard (200...299).contains(status) else { throw failure(status, data, route) }
        return try decode(Item.self, data, route)
    }
}

/// Subtitle timing (arc-media-server#479), as the web's and Android's: half a second at a time,
/// up to ten seconds either way, kept per file and track for this playback only (not saved).
/// Positive shows the subtitles later.
public enum SubtitleTiming {
    public static let stepMs: Int64 = 500
    public static let maxMs: Int64 = 10_000

    /// Offsets are kept by file and track.
    public static func key(fileId: Int64, trackId: String) -> String { "\(fileId):\(trackId)" }

    /// The offset after a nudge of `deltaMs`, or 0 for Reset (`deltaMs` nil).
    public static func shifted(_ currentMs: Int64, _ deltaMs: Int64?) -> Int64 {
        guard let deltaMs else { return 0 }
        return min(maxMs, max(-maxMs, currentMs + deltaMs))
    }

    /// The point in the subtitles to show at `positionMs`: a later offset shows earlier lines.
    public static func cueTimeMs(_ positionMs: Int64, offsetMs: Int64) -> Int64 { positionMs - offsetMs }

    /// "+1.5", "−0.5" (a true minus) or "0.0": the seconds, written as every Arc app writes them.
    public static func seconds(_ ms: Int64) -> String {
        let tenths = abs(ms) / 100
        let body = "\(tenths / 10).\(tenths % 10)"
        return ms > 0 ? "+" + body : ms < 0 ? "\u{2212}" + body : body
    }
}
