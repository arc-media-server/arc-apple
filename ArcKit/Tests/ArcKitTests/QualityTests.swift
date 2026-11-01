import XCTest
@testable import ArcKit

/// A file's badges read as the title page shows them, from the fields Arc's items/{id} has.
final class QualityTests: XCTestCase {
    private func file(_ streams: String) throws -> MediaFile {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(MediaFile.self, from: Data(#"{"id":1,"streams":[\#(streams)]}"#.utf8))
    }

    func testA4KDolbyVisionFileWithAtmos() throws {
        let f = try file(#"{"kind":"video","codec":"hevc","width":3840,"height":1600,"color_transfer":"smpte2084","dolby_vision":true},{"kind":"audio","codec":"eac3","profile":"Dolby Digital Plus + Dolby Atmos","channels":6,"is_default":true}"#)
        XCTAssertEqual(Quality.badges(f), ["4K", "DV HDR10", "DD+ 5.1", "Atmos"])
    }

    func testOrdinaryFilesAndTheDefaultTrack() throws {
        let f = try file(#"{"kind":"video","codec":"h264","width":1920,"height":1080},{"kind":"audio","codec":"aac","channels":2},{"kind":"audio","codec":"dts","profile":"DTS-HD MA + DTS:X","channels":8,"is_default":true}"#)
        XCTAssertEqual(Quality.badges(f), ["HD", "DTS-HD MA 7.1", "DTS:X"])
        XCTAssertEqual(Quality.badges(try file(#"{"kind":"video","codec":"mpeg2video","width":720,"height":576}"#)), ["SD"])
        XCTAssertEqual(Quality.badges(try file(#"{"kind":"video","codec":"hevc","width":3840,"height":2160,"color_transfer":"arib-std-b67"}"#)), ["4K", "HLG"])
        XCTAssertEqual(Quality.badges(try file("")), [])
        XCTAssertEqual(Quality.badges(nil), [])
    }
}
