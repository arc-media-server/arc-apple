import XCTest
@testable import ArcKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The player's choices match the web player's.
final class PlayerLogicTests: XCTestCase {
    private let tracks = [
        SubtitleTrack(id: "f", language: "eng", forced: true),
        SubtitleTrack(id: "sdh", language: "eng", hearingImpaired: true),
        SubtitleTrack(id: "en", language: "en"),
        SubtitleTrack(id: "fr", language: "fre"),
        SubtitleTrack(id: "pgs", language: "ger", image: true),
    ]

    func testLanguagesMatchWhateverCodeTheyUse() {
        XCTAssertTrue(sameLanguage("eng", "en"))
        XCTAssertTrue(sameLanguage("en-GB", "EN"))
        XCTAssertTrue(sameLanguage("fre", "fra"))
        XCTAssertFalse(sameLanguage("und", "und"))
        XCTAssertFalse(sameLanguage(nil, "en"))
        XCTAssertFalse(sameLanguage("de", "en"))
    }

    func testSubtitleModesPickAsPlexDoes() {
        // The language last chosen: the plain track, not forced or SDH.
        XCTAssertEqual(chooseSubtitle(tracks, preferred: "en", audioLanguage: "en", mode: "")?.id, "en")
        XCTAssertEqual(chooseSubtitle(tracks, preferred: "en", audioLanguage: "en", mode: "always")?.id, "en")
        // Foreign: only when the audio is in another language; otherwise forced ones in the audio's.
        XCTAssertEqual(chooseSubtitle(tracks, preferred: "en", audioLanguage: "ja", mode: "foreign")?.id, "en")
        XCTAssertEqual(chooseSubtitle(tracks, preferred: "en", audioLanguage: "eng", mode: "foreign")?.id, "f")
        // Manual: forced only.
        XCTAssertEqual(chooseSubtitle(tracks, preferred: "fr", audioLanguage: "en", mode: "manual")?.id, "f")
        XCTAssertNil(chooseSubtitle(tracks, preferred: "", audioLanguage: "ja", mode: "manual"))
        // A picture track is used when it's the only one in the language.
        XCTAssertEqual(chooseSubtitle(tracks, preferred: "de", audioLanguage: "en", mode: "")?.id, "pgs")
    }

    func testWhatAChoiceRemembers() {
        XCTAssertEqual(rememberedSubtitleLanguage(tracks[3], mode: ""), "fre")
        XCTAssertNil(rememberedSubtitleLanguage(tracks[0], mode: ""))
        XCTAssertEqual(rememberedSubtitleLanguage(nil, mode: ""), "")
        XCTAssertNil(rememberedSubtitleLanguage(nil, mode: "always"))
    }

    func testTheCueShowingAtATime() {
        let cues = [SubtitleCue(startMs: 1000, endMs: 3000, text: "a"), SubtitleCue(startMs: 2500, endMs: 4000, text: "b"),
                    SubtitleCue(startMs: 6000, endMs: 7000, text: "c")]
        XCTAssertNil(cue(at: 500, in: cues))
        XCTAssertEqual(cue(at: 1000, in: cues)?.text, "a")
        XCTAssertEqual(cue(at: 2600, in: cues)?.text, "b")
        XCTAssertEqual(cue(at: 3500, in: cues)?.text, "b")
        XCTAssertNil(cue(at: 5000, in: cues))
        XCTAssertEqual(cue(at: 6999, in: cues)?.text, "c")
        XCTAssertNil(cue(at: 7000, in: cues))
        XCTAssertNil(cue(at: 10, in: []))
    }

    func testMarkersAndUpNext() {
        let markers = [Marker(kind: "intro", startMs: 60_000, endMs: 90_000), Marker(kind: "credits", startMs: 1_200_000, endMs: 1_300_000)]
        XCTAssertNil(activeMarker(markers, at: 10_000))
        XCTAssertEqual(activeMarker(markers, at: 60_000)?.kind, "intro")
        // Not in its last second: skipping then would be a jump of nothing.
        XCTAssertNil(activeMarker(markers, at: 89_500))
        XCTAssertFalse(showsUpNext(markers: markers, positionMs: 1_199_000, durationMs: 1_300_000))
        XCTAssertTrue(showsUpNext(markers: markers, positionMs: 1_200_000, durationMs: 1_300_000))
        XCTAssertFalse(showsUpNext(markers: [], positionMs: 1_260_000, durationMs: 1_300_000))
        XCTAssertTrue(showsUpNext(markers: [], positionMs: 1_271_000, durationMs: 1_300_000))
    }
}

final class PlayerAPITests: XCTestCase {
    private var api: ArcAPI!

    override func setUp() {
        StubArc.answers = []
        StubArc.requests = []
        StubArc.bodies = []
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubArc.self]
        api = ArcAPI(baseURL: URL(string: "http://arc.test:8099")!, session: URLSession(configuration: config), token: { "t0k" })
    }

    func testCuesNextEpisodeAndTheLastOne() async throws {
        StubArc.answers = [
            .init(status: 200, body: #"{"track":{"id":"s:3"},"cues":[{"start_ms":1000,"end_ms":2000,"text":"Hello"}]}"#),
            .init(status: 200, body: #"{"id":"e2","kind":"episode","title":"Two","season_number":1,"episode_number":2}"#),
            .init(status: 204, body: ""),
        ]
        let cues = try await api.subtitleCues(itemId: "e1", track: "s:3", fileId: 7)
        XCTAssertEqual(cues, [SubtitleCue(startMs: 1000, endMs: 2000, text: "Hello")])
        XCTAssertEqual(StubArc.requests[0].url?.absoluteString, "http://arc.test:8099/api/v1/items/e1/subtitles/s%3A3?file=7")
        let next = try await api.nextEpisode("e1")
        XCTAssertEqual(next?.episodeNumber, 2)
        let none = try await api.nextEpisode("e2")
        XCTAssertNil(none)
    }

    func testABurnedInSubtitleIsAskedFor() throws {
        let caps = PlayerCaps(containers: ["mp4"], video: ["h264"], audio: ["aac"], maxHeight: 1080)
        let body = String(decoding: try ArcJSON.encoder.encode(PlaybackRequest(caps: caps, startMs: 5, audioStream: 2, burnSubtitle: "s:4")), as: UTF8.self)
        XCTAssertTrue(body.contains(#""burn_subtitle":"s:4""#), body)
        XCTAssertTrue(body.contains(#""audio_stream":2"#), body)
    }

    func testSubtitleTiming() {
        XCTAssertEqual(SubtitleTiming.shifted(0, SubtitleTiming.stepMs), 500)
        XCTAssertEqual(SubtitleTiming.shifted(-500, -500), -1_000)
        XCTAssertEqual(SubtitleTiming.shifted(10_000, 500), 10_000)
        XCTAssertEqual(SubtitleTiming.shifted(-10_000, -500), -10_000)
        XCTAssertEqual(SubtitleTiming.shifted(3_000, nil), 0)
        XCTAssertEqual(SubtitleTiming.key(fileId: 7, trackId: "s:2"), "7:s:2")
        // Later subtitles show the line that was due earlier.
        let cues = [SubtitleCue(startMs: 1_000, endMs: 2_000, text: "one"), SubtitleCue(startMs: 3_000, endMs: 4_000, text: "two")]
        XCTAssertEqual(cue(at: SubtitleTiming.cueTimeMs(2_500, offsetMs: 1_000), in: cues)?.text, "one")
        XCTAssertEqual(cue(at: SubtitleTiming.cueTimeMs(2_500, offsetMs: -1_000), in: cues)?.text, "two")
        XCTAssertEqual(SubtitleTiming.seconds(1_500), "+1.5")
        XCTAssertEqual(SubtitleTiming.seconds(-500), "\u{2212}0.5")
        XCTAssertEqual(SubtitleTiming.seconds(0), "0.0")
        XCTAssertEqual(SubtitleTiming.seconds(10_000), "+10.0")
    }
}
