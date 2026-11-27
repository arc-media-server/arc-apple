import XCTest
@testable import ArcKit

final class PlaybackStatsTests: XCTestCase {
    func testDynamicRange() {
        XCTAssertEqual(StatsFormat.dynamicRange(transfer: "pq", dolbyVisionProfile: nil), "HDR10")
        XCTAssertEqual(StatsFormat.dynamicRange(transfer: "smpte2084", dolbyVisionProfile: nil), "HDR10")
        XCTAssertEqual(StatsFormat.dynamicRange(transfer: "arib-std-b67", dolbyVisionProfile: nil), "HLG")
        XCTAssertEqual(StatsFormat.dynamicRange(transfer: "bt.1886", dolbyVisionProfile: nil), "SDR")
        XCTAssertEqual(StatsFormat.dynamicRange(transfer: "pq", dolbyVisionProfile: 8), "Dolby Vision P8")
        XCTAssertEqual(StatsFormat.dynamicRange(transfer: nil, dolbyVisionProfile: nil, dolbyVision: true), "Dolby Vision")
        XCTAssertNil(StatsFormat.dynamicRange(transfer: nil, dolbyVisionProfile: nil))
    }

    func testVideoAndAudio() {
        XCTAssertEqual(StatsFormat.video(codec: "hevc", width: 3840, height: 2160, frameRate: 23.976), "HEVC · 3840×2160 · 23.976 fps")
        XCTAssertEqual(StatsFormat.video(codec: nil, width: 1920, height: 1080, frameRate: 25), "1920×1080 · 25 fps")
        XCTAssertNil(StatsFormat.video(codec: nil, width: 0, height: 0, frameRate: nil))
        XCTAssertEqual(StatsFormat.audio(codec: "eac3", channels: 6), "EAC3 5.1")
        XCTAssertEqual(StatsFormat.audio(codec: "aac", channels: 2), "AAC 2.0")
        XCTAssertEqual(StatsFormat.fps(59.94), "59.94")
        XCTAssertEqual(StatsFormat.mbps(12_400), "12.4 Mbps")
        XCTAssertEqual(StatsFormat.seconds(-1), "0.0 s")
    }
}
