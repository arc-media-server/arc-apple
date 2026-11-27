import Foundation

/// What the player is really doing, for Playback Info ("stats for nerds", as Android's): what
/// each engine can tell, nil where it can't.
public struct EngineStats: Equatable, Sendable {
    public var videoCodec: String?
    public var width = 0
    public var height = 0
    public var frameRate: Double?
    /// The picture's transfer curve: mpv's names ("pq", "hlg") or the server's ("smpte2084",
    /// "arib-std-b67"); anything else is SDR.
    public var transfer: String?
    public var dolbyVisionProfile: Int?
    /// Whether the video decodes in hardware (VideoToolbox), when the engine says.
    public var hardwareDecoding: Bool?
    public var audioCodec: String?
    public var audioChannels: Int?
    /// Dolby Digital (Plus) goes to Apple's own decoder whole (Atmos kept), not decoded to PCM.
    public var audioToAppleDecoder: Bool?
    public var droppedFrames: Int?
    public var bufferedSeconds: Double?
    /// How fast the stream arrives from Arc (kbit/s).
    public var downloadKbps: Int?
    /// Times playback stopped to wait for data.
    public var waits: Int?

    public init() {}
}

/// The values in Playback Info, written the same way in every app.
public enum StatsFormat {
    /// "Dolby Vision P8", "HDR10", "HLG" or "SDR"; nil when nothing is known.
    public static func dynamicRange(transfer: String?, dolbyVisionProfile: Int?, dolbyVision: Bool = false) -> String? {
        if let profile = dolbyVisionProfile, profile > 0 { return "Dolby Vision P\(profile)" }
        if dolbyVision { return "Dolby Vision" }
        guard let transfer, !transfer.isEmpty else { return nil }
        switch transfer.lowercased() {
        case "pq", "smpte2084", "st2084": return "HDR10"
        case "hlg", "arib-std-b67": return "HLG"
        default: return "SDR"
        }
    }

    /// "HEVC · 3840×2160 · 23.976 fps", with whatever is known.
    public static func video(codec: String?, width: Int, height: Int, frameRate: Double?) -> String? {
        var parts: [String] = []
        if let codec, !codec.isEmpty { parts.append(codecName(codec)) }
        if width > 0 && height > 0 { parts.append("\(width)×\(height)") }
        if let frameRate, frameRate > 0 { parts.append(fps(frameRate) + " fps") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "EAC3 5.1", "AAC 2.0".
    public static func audio(codec: String?, channels: Int?) -> String? {
        var parts: [String] = []
        if let codec, !codec.isEmpty { parts.append(codec.uppercased()) }
        if let channels, channels > 0 { parts.append(channelLayout(channels)) }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// 1 → "1.0", 2 → "2.0", 6 → "5.1", 8 → "7.1".
    public static func channelLayout(_ channels: Int) -> String {
        channels <= 2 ? "\(channels).0" : "\(channels - 1).1"
    }

    /// "23.976", "25", "59.94".
    public static func fps(_ rate: Double) -> String {
        var text = String(format: "%.3f", rate)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// "12.4 Mbps".
    public static func mbps(_ kbps: Int) -> String { String(format: "%.1f Mbps", Double(kbps) / 1000) }

    /// "8.5 s".
    public static func seconds(_ value: Double) -> String { String(format: "%.1f s", max(0, value)) }
}
