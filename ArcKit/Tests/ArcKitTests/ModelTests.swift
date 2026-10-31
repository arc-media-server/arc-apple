import XCTest
@testable import ArcKit

final class ModelTests: XCTestCase {
    func testMissingAndNullFieldsTakeTheirUsualValues() throws {
        let json = #"{"id":"m1","kind":"movie","title":"Heat","genres":null,"new_field":{"x":1},"user_data":{"position_ms":60000},"files":[{"id":3,"duration_ms":600000}]}"#
        let item = try ArcJSON.decoder.decode(Item.self, from: Data(json.utf8))
        XCTAssertEqual(item.genres, [])
        XCTAssertEqual(item.resumeMs, 60_000)
        XCTAssertEqual(item.durationMs, 600_000)
        XCTAssertFalse(item.watched)
        XCTAssertEqual(MediaCard(item: item).progress ?? 0, 0.1, accuracy: 0.0001)

        let prefs = try ArcJSON.decoder.decode(Prefs.self, from: Data("{}".utf8))
        XCTAssertTrue(prefs.autoPlay)
        XCTAssertEqual(prefs.home, [])

        let profile = try ArcJSON.decoder.decode(Profile.self, from: Data(#"{"id":"u1","name":"Jo","has_pin":true}"#.utf8))
        XCTAssertEqual(profile.color, "violet")
        XCTAssertTrue(profile.hasPin)
    }

    func testThePlaybackRequestIsSentAsArcReadsIt() throws {
        let caps = PlayerCaps(containers: ["mp4"], video: ["h264", "hevc"], audio: ["aac", "eac3"], maxHeight: 2160,
                              hdrFormats: ["hdr10", "dolby_vision"], dolbyVisionProfiles: [5, 8])
        let body = String(decoding: try ArcJSON.encoder.encode(PlaybackRequest(caps: caps, startMs: 5000)), as: UTF8.self)
        XCTAssertEqual(body, #"{"caps":{"audio":["aac","eac3"],"audio_passthrough":[],"containers":["mp4"],"dolby_vision_profiles":[5,8],"hdr_formats":["hdr10","dolby_vision"],"max_height":2160,"video":["h264","hevc"]},"start_ms":5000}"#)
        XCTAssertEqual(caps.fallback(after: "direct").video, ["h264", "hevc"])
        XCTAssertEqual(caps.fallback(after: "remux").video, [])
        XCTAssertEqual(caps.fallback(after: "remux").containers, [])
    }

    func testAConvertedStreamsClockStartsAtItsOffset() {
        let converted = PlaybackPlan(method: "transcode", url: "/api/transcode/s/index.m3u8", hls: true, sessionId: "s", offsetMs: 600_000)
        let direct = PlaybackPlan(method: "direct", url: "/api/items/m1/stream?file=1")
        XCTAssertEqual(PlaybackClock.filePosition(converted, playerMs: 15_000), 615_000)
        XCTAssertEqual(PlaybackClock.filePosition(direct, playerMs: 15_000), 15_000)
        XCTAssertEqual(PlaybackClock.playerStart(converted, fileMs: 605_000), 5_000)
        XCTAssertEqual(PlaybackClock.playerStart(converted, fileMs: 500_000), 0)
        XCTAssertTrue(PlaybackClock.seekInStream(converted, fileMs: 700_000, availableMs: 300_000))
        XCTAssertFalse(PlaybackClock.seekInStream(converted, fileMs: 500_000, availableMs: 300_000))
        XCTAssertTrue(PlaybackClock.seekInStream(direct, fileMs: 5_000_000, availableMs: 0))
    }
}
