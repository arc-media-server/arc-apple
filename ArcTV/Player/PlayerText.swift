import ArcKit
import Foundation

/// How the player writes times, speeds and tracks, on Apple TV and iPhone and iPad alike.
enum PlayerText {
    static func time(_ ms: Int64) -> String {
        let s = Int(ms / 1000)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    static func speedName(_ speed: Float) -> String {
        speed.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// "24 Oct 2026", from the server's yyyy-MM-dd.
    static func day(_ iso: String) -> String? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: iso) else { return nil }
        let out = DateFormatter()
        out.setLocalizedDateFormatFromTemplate("d MMM yyyy")
        return out.string(from: d)
    }

    /// "Timing: +1.5s (later)", "Timing: −0.5s (earlier)" or "Timing: 0.0s".
    static func timingName(_ ms: Int64) -> String {
        let seconds = SubtitleTiming.seconds(ms)
        return ms > 0 ? L("player.timing_later", seconds) : ms < 0 ? L("player.timing_earlier", seconds) : L("player.timing_zero")
    }

    static func trackName(_ t: SubtitleTrack) -> String {
        var parts = [languageName(t.language) ?? t.title ?? L("player.unknown_language")]
        if let title = t.title, !title.isEmpty, parts.first != title { parts.append(title) }
        if t.forced { parts.append(L("player.forced")) }
        if t.hearingImpaired { parts.append(L("player.sdh")) }
        return parts.joined(separator: " · ")
    }

    static func audioName(_ a: AudioTrack) -> String {
        var parts = [languageName(a.language) ?? a.title ?? L("player.unknown_language")]
        if !a.codec.isEmpty { parts.append(a.codec.uppercased()) }
        switch a.channels {
        case 0: break
        case 1: parts.append(L("player.mono"))
        case 2: parts.append(L("player.stereo"))
        default: parts.append("\(a.channels - 1).1")
        }
        return parts.joined(separator: " · ")
    }

    private static func languageName(_ code: String?) -> String? {
        guard let code, !code.isEmpty, code != "und" else { return nil }
        return Locale.current.localizedString(forLanguageCode: code) ?? code
    }
}
