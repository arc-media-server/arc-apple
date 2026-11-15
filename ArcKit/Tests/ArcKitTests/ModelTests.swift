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

    func testEpisodesOutsideTheOrderComeAfterTheSeasons() throws {
        let json = #"""
        {"series":{"id":"s1","kind":"series","title":"Firefly"},
         "seasons":[{"season_number":1,"episodes":[{"id":"e1","kind":"episode","title":"Serenity","season_number":1,"episode_number":1}]}],
         "unplaced":[{"id":"e9","kind":"episode","title":"Unaired Pilot"},{"id":"e10","kind":"episode","title":"Not Out","available":false}]}
        """#
        let answer = try ArcJSON.decoder.decode(SeasonsResponse.self, from: Data(json.utf8))
        let tabs = answer.tabs(unplacedName: "Not in This Order")
        XCTAssertEqual(tabs.map(\.name), ["", "Not in This Order"])
        XCTAssertEqual(tabs.map(\.isUnplaced), [false, true])
        XCTAssertEqual(tabs[1].episodes.map(\.id), ["e9", "e10"])
        // The player's Episodes card: the episode's own tab, playable episodes only.
        let outside = try XCTUnwrap(answer.tab(containing: "e9"))
        XCTAssertTrue(outside.isUnplaced)
        XCTAssertEqual(outside.episodes.map(\.id), ["e9"])
        XCTAssertEqual(answer.tab(containing: "e1")?.seasonNumber, 1)
        XCTAssertNil(answer.tab(containing: "nope"))
    }

    func testAShowWithEverythingInItsOrderHasOnlyItsSeasons() throws {
        for unplaced in [#""unplaced":null,"#, #""unplaced":[],"#, ""] {
            let json = #"{"# + unplaced + #""series":{"id":"s1","kind":"series","title":"Firefly"},"seasons":[{"season_number":1}]}"#
            let answer = try ArcJSON.decoder.decode(SeasonsResponse.self, from: Data(json.utf8))
            XCTAssertTrue(answer.unplaced.isEmpty)
            XCTAssertEqual(answer.tabs(unplacedName: "Not in This Order").map(\.seasonNumber), [1])
        }
    }

    func testAnEpisodeOutsideTheOrderHasNoEpisodeCode() throws {
        func item(_ json: String) throws -> Item { try ArcJSON.decoder.decode(Item.self, from: Data(json.utf8)) }
        XCTAssertTrue(try item(#"{"id":"e1","kind":"episode","title":"Serenity","season_number":1,"episode_number":1}"#).hasEpisodeCode)
        // A special keeps its number.
        XCTAssertTrue(try item(#"{"id":"e2","kind":"episode","title":"Making Of","season_number":0,"episode_number":3}"#).hasEpisodeCode)
        // Arc sends 0 and 0 for an episode the order doesn't place.
        XCTAssertFalse(try item(#"{"id":"e9","kind":"episode","title":"Unaired Pilot","season_number":0,"episode_number":0}"#).hasEpisodeCode)
        XCTAssertFalse(try item(#"{"id":"e10","kind":"episode","title":"Unaired Pilot"}"#).hasEpisodeCode)
        XCTAssertFalse(try item(#"{"id":"m1","kind":"movie","title":"Serenity","season_number":1,"episode_number":1}"#).hasEpisodeCode)
    }
}
