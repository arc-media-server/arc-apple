import Foundation

/// What a title's file is, as short badges for its page (4K, DV HDR10, DD+ 5.1, Atmos):
/// labels for the source, not for what this TV will output. The web's `sourceFormats` and
/// `audioFormat` read the same fields.
public enum Quality {
    /// The file a title's page describes: the first one on disk.
    public static func file(of item: Item) -> MediaFile? {
        item.files.first { !$0.missing } ?? item.files.first
    }

    public static func badges(_ file: MediaFile?) -> [String] {
        guard let file else { return [] }
        var out: [String] = []
        if let video = file.streams.first(where: { $0.kind == "video" }) {
            if let res = resolution(video) { out.append(res) }
            if let hdr = hdr(video) { out.append(hdr) }
        }
        let audios = file.streams.filter { $0.kind == "audio" }
        if let audio = audios.first(where: \.isDefault) ?? audios.first {
            let line = [audioCodec(audio), channels(audio.channels)].compactMap { $0 }.joined(separator: " ")
            if !line.isEmpty { out.append(line) }
            if let object = objectAudio(audio) { out.append(object) }
        }
        return out
    }

    /// A badge on a title's page, as the reference design draws them: the resolution filled
    /// ("4K", "1080p"), then capsules whose parts are split by a line ("DV | HDR10", "DD+ | 5.1",
    /// "Atmos").
    public struct Capsule: Equatable, Sendable {
        public let parts: [String]
        public let filled: Bool
        public init(_ parts: [String], filled: Bool = false) {
            self.parts = parts
            self.filled = filled
        }
    }

    public static func capsules(_ file: MediaFile?) -> [Capsule] {
        guard let file else { return [] }
        var out: [Capsule] = []
        if let video = file.streams.first(where: { $0.kind == "video" }) {
            if let res = resolutionLabel(video) { out.append(Capsule([res], filled: true)) }
            switch hdr(video) {
            case "DV HDR10": out.append(Capsule(["DV", "HDR10"]))
            case "DV HDR10+": out.append(Capsule(["DV", "HDR10+"]))
            case let h?: out.append(Capsule([h]))
            case nil: out.append(Capsule(["SDR"]))
            }
        }
        let audios = file.streams.filter { $0.kind == "audio" }
        if let audio = audios.first(where: \.isDefault) ?? audios.first {
            let parts = [audioCodec(audio), channels(audio.channels)].compactMap { $0 }
            if !parts.isEmpty { out.append(Capsule(parts)) }
            if let object = objectAudio(audio) { out.append(Capsule([object])) }
        }
        return out
    }

    /// The file's quality in words, for the title page's Playback card: the resolution, the
    /// picture's HDR, and the sound ("4K · Dolby Vision · Dolby Atmos", "1080p · DTS-HD MA 7.1").
    public static func summary(_ file: MediaFile?) -> String? {
        guard let file else { return nil }
        var parts: [String] = []
        if let video = file.streams.first(where: { $0.kind == "video" }) {
            if let res = resolutionLabel(video) { parts.append(res) }
            if video.dolbyVision {
                parts.append("Dolby Vision")
            } else if let h = hdr(video) {
                parts.append(h)
            }
        }
        let audios = file.streams.filter { $0.kind == "audio" }
        if let audio = audios.first(where: \.isDefault) ?? audios.first {
            if objectAudio(audio) == "Atmos" {
                parts.append("Dolby Atmos")
            } else if let object = objectAudio(audio) {
                parts.append(object)
            } else {
                let line = [audioCodec(audio), channels(audio.channels)].compactMap { $0 }.joined(separator: " ")
                if !line.isEmpty { parts.append(line) }
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 4K, 1080p, 720p or SD by the picture's size (a scope film's 3840x1600 is still 4K, and
    /// 1920x800 still 1080p).
    public static func resolutionLabel(_ video: MediaStream) -> String? {
        guard let w = video.width, let h = video.height, w > 0, h > 0 else { return nil }
        if w >= 3200 || h >= 1700 { return "4K" }
        if w >= 1800 || h >= 1000 { return "1080p" }
        if w >= 1200 || h >= 700 { return "720p" }
        return "SD"
    }

    /// 4K, HD or SD by the picture's size (a scope film's 3840x1600 is still 4K).
    public static func resolution(_ video: MediaStream) -> String? {
        guard let w = video.width, let h = video.height, w > 0, h > 0 else { return nil }
        if w >= 3200 || h >= 1700 { return "4K" }
        if w >= 1200 || h >= 700 { return "HD" }
        return "SD"
    }

    /// Dolby Vision with its HDR10 base reads "DV HDR10".
    public static func hdr(_ video: MediaStream) -> String? {
        let pq = video.colorTransfer == "smpte2084"
        if video.dolbyVision { return pq ? (video.hdr10Plus ? "DV HDR10+" : "DV HDR10") : "DV" }
        if video.hdr10Plus { return "HDR10+" }
        if pq { return "HDR10" }
        if video.colorTransfer == "arib-std-b67" { return "HLG" }
        return nil
    }

    public static func audioCodec(_ audio: MediaStream) -> String? {
        let p = audio.profile?.lowercased() ?? ""
        switch audio.codec {
        case "eac3": return "DD+"
        case "ac3": return "DD"
        case "truehd": return "TrueHD"
        case "dts":
            if p.hasPrefix("dts-hd ma") { return "DTS-HD MA" }
            if p.hasPrefix("dts-hd hra") { return "DTS-HD HRA" }
            return "DTS"
        case "aac": return "AAC"
        case "flac": return "FLAC"
        case "opus": return "Opus"
        case "mp3": return "MP3"
        case "": return nil
        default: return audio.codec.hasPrefix("pcm") ? "PCM" : audio.codec.uppercased()
        }
    }

    public static func channels(_ n: Int?) -> String? {
        switch n {
        case nil, 0: return nil
        case 1: return "1.0"
        case 2: return "2.0"
        case 6: return "5.1"
        case 8: return "7.1"
        case let n?: return "\(n)ch"
        }
    }

    /// Atmos or DTS:X, from the track's profile as ffprobe names it.
    public static func objectAudio(_ audio: MediaStream) -> String? {
        let p = audio.profile?.lowercased() ?? ""
        if p.contains("atmos") { return "Atmos" }
        if p.contains("dts:x") { return "DTS:X" }
        return nil
    }
}
