import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Quality, versions, chapters, timeline thumbnails and extras, as the web player has them.

/// One of a title's files: an edition or another copy.
public struct Version: Codable, Sendable, Hashable, Identifiable {
    public let fileId: Int64
    public var edition: String?
    public var width: Int?
    public var height: Int?
    public var videoCodec: String?
    /// HDR10 or HLG.
    public var hdr: String?
    @Default<Defaults.List<String>> public var sourceFormats: [String]
    @Default<Defaults.Zero64> public var size: Int64
    public var id: Int64 { fileId }

    public init(fileId: Int64, edition: String? = nil, width: Int? = nil, height: Int? = nil, videoCodec: String? = nil, hdr: String? = nil, size: Int64 = 0) {
        self.fileId = fileId
        self.edition = edition
        self.width = width
        self.height = height
        self.videoCodec = videoCodec
        self.hdr = hdr
        self.size = size
    }

    /// e.g. "Director's Cut · 4K · HDR10 · HEVC · 58 GB" (the edition first when it has one).
    public var label: String {
        var parts: [String] = []
        if let edition, !edition.isEmpty { parts.append(edition) }
        if let w = width, let h = height, w > 0 { parts.append(resolutionName(width: w, height: h)) }
        if !sourceFormats.isEmpty { parts += sourceFormats } else if let hdr, !hdr.isEmpty { parts.append(hdr) }
        if let c = videoCodec, !c.isEmpty { parts.append(codecName(c)) }
        if size > 0 { parts.append(fileSize(size)) }
        return parts.joined(separator: " · ")
    }
}

/// A chapter mark in the file.
public struct Chapter: Codable, Sendable, Hashable {
    public let startMs: Int64
    @Default<Defaults.Zero64> public var endMs: Int64
    public var title: String?

    public init(startMs: Int64, endMs: Int64 = 0, title: String? = nil) {
        self.startMs = startMs
        self.endMs = endMs
        self.title = title
    }
}

/// A trailer or other extra on a title's page.
public struct Extra: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    /// trailer, featurette, behindthescenes, deleted, interview, scene, short, other.
    @Default<Defaults.Empty> public var kind: String
    public let title: String
    @Default<Defaults.Zero64> public var durationMs: Int64
    public let streamUrl: String

    public init(id: String, kind: String, title: String, durationMs: Int64 = 0, streamUrl: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.durationMs = durationMs
        self.streamUrl = streamUrl
    }
}

/// Where a file's timeline thumbnails are: a grid of them on each sheet picture.
public struct Trickplay: Codable, Sendable {
    public struct Info: Codable, Sendable {
        public let intervalMs: Int64
        public let width: Int
        public let height: Int
        public let columns: Int
        public let rows: Int
        public let count: Int
    }

    public let info: Info
    @Default<Defaults.List<String>> public var sheets: [String]

    /// The sheet and the thumbnail's place on it (in pixels) for a time in the file.
    public func thumbnail(at ms: Int64) -> (sheet: String, x: Int, y: Int)? {
        guard info.intervalMs > 0, info.columns > 0, info.rows > 0, info.count > 0 else { return nil }
        let index = min(Int(max(0, ms) / info.intervalMs), info.count - 1)
        let perSheet = info.columns * info.rows
        let sheet = index / perSheet
        guard sheets.indices.contains(sheet) else { return nil }
        let cell = index % perSheet
        return (sheets[sheet], (cell % info.columns) * info.width, (cell / info.columns) * info.height)
    }
}

/// The quality limits the player offers (kbit/s), as Plex's and the web's.
public let qualityLimits = [20000, 12000, 8000, 4000, 3000, 2000, 1500, 720]

/// The limits worth offering for a file: only ones below its own bitrate (all when it's unknown).
public func offeredQualities(sourceKbps: Int) -> [Int] {
    sourceKbps > 0 ? qualityLimits.filter { $0 < sourceKbps } : qualityLimits
}

/// e.g. "4 Mbps 720p" or "720 kbps 360p".
public func qualityName(_ kbps: Int) -> String {
    let height = kbps >= 8000 ? 1080 : kbps >= 2000 ? 720 : kbps >= 1500 ? 480 : 360
    let rate = kbps >= 1000 ? (kbps % 1000 == 0 ? "\(kbps / 1000) Mbps" : String(format: "%.1f Mbps", Double(kbps) / 1000)) : "\(kbps) kbps"
    return "\(rate) \(height)p"
}

func resolutionName(width: Int, height: Int) -> String {
    // By width as well, so cropped widescreen films count as what they are.
    if width >= 3200 || height >= 2000 { return "4K" }
    if width >= 1800 || height >= 1000 { return "1080p" }
    if width >= 1200 || height >= 700 { return "720p" }
    return "SD"
}

func codecName(_ codec: String) -> String {
    switch codec.lowercased() {
    case "hevc", "h265": return "HEVC"
    case "h264", "avc": return "H.264"
    case "av1": return "AV1"
    case "vp9": return "VP9"
    case "mpeg2video": return "MPEG-2"
    default: return codec.uppercased()
    }
}

func fileSize(_ bytes: Int64) -> String {
    let gb = Double(bytes) / 1_000_000_000
    if gb >= 10 { return "\(Int(gb.rounded())) GB" }
    if gb >= 1 { return String(format: "%.1f GB", gb) }
    return "\(Int((Double(bytes) / 1_000_000).rounded())) MB"
}

extension ArcAPI {
    /// A file's timeline thumbnails; nil while they aren't made (or they're off for the library).
    public func trickplay(itemId: String, fileId: Int64) async throws -> Trickplay? {
        let route = "items/{id}/trickplay"
        let (status, data) = try await raw("GET", "items/\(enc(itemId))/trickplay?file=\(fileId)", route: route)
        if status == 404 { return nil }
        guard (200...299).contains(status) else { throw failure(status, data, route) }
        return try decode(Trickplay.self, data, route)
    }
}
