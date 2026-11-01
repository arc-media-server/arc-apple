import XCTest
@testable import ArcKit

/// Quality, versions, chapters, thumbnails and extras read and label as the web player's.
final class PlayerExtrasTests: XCTestCase {
    func testQualitiesBelowTheFilesOwnBitrate() {
        XCTAssertEqual(offeredQualities(sourceKbps: 5000), [4000, 3000, 2000, 1500, 720])
        XCTAssertEqual(offeredQualities(sourceKbps: 0), qualityLimits)
        XCTAssertEqual(qualityName(4000), "4 Mbps 720p")
        XCTAssertEqual(qualityName(1500), "1.5 Mbps 480p")
        XCTAssertEqual(qualityName(720), "720 kbps 360p")
    }

    func testVersionLabels() {
        XCTAssertEqual(Version(fileId: 1, edition: "Director's Cut", width: 1920, height: 800, videoCodec: "h264", size: 14_000_000_000).label,
                       "Director's Cut · 1080p · H.264 · 14 GB")
        XCTAssertEqual(Version(fileId: 2, width: 3840, height: 1600, videoCodec: "hevc", hdr: "HDR10", size: 5_500_000_000).label,
                       "4K · HDR10 · HEVC · 5.5 GB")
    }

    func testTheThumbnailForATime() throws {
        let json = #"{"info":{"interval_ms":10000,"width":320,"height":180,"columns":4,"rows":3,"count":20},"sheets":["/a/0","/a/1"]}"#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let t = try decoder.decode(Trickplay.self, from: Data(json.utf8))
        XCTAssertEqual(t.thumbnail(at: 0)?.sheet, "/a/0")
        let fifth = try XCTUnwrap(t.thumbnail(at: 55_000))
        XCTAssertEqual(fifth.sheet, "/a/0")
        XCTAssertEqual(fifth.x, 320)
        XCTAssertEqual(fifth.y, 180)
        let late = try XCTUnwrap(t.thumbnail(at: 120_000))
        XCTAssertEqual(late.sheet, "/a/1")
        XCTAssertEqual(late.x, 0)
        // Past the end: the last thumbnail.
        XCTAssertEqual(t.thumbnail(at: 9_999_999)?.sheet, "/a/1")
    }

    func testExtrasAndChaptersReadWithTheirDefaults() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let e = try decoder.decode(Extra.self, from: Data(#"{"id":"x","title":"Trailer","stream_url":"/api/extras/x/stream"}"#.utf8))
        XCTAssertEqual(e.kind, "")
        XCTAssertEqual(e.durationMs, 0)
        let c = try decoder.decode(Chapter.self, from: Data(#"{"start_ms":4000}"#.utf8))
        XCTAssertEqual(c.startMs, 4000)
        XCTAssertNil(c.title)
    }
}
