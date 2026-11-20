import XCTest
@testable import ArcKit

final class SpoilerTests: XCTestCase {
    private func item(_ json: String) throws -> Item { try ArcJSON.decoder.decode(Item.self, from: Data(json.utf8)) }

    func testOnlyUnstartedEpisodesAreHidden() throws {
        let fresh = try item(#"{"id":"e1","kind":"episode","title":"Pilot"}"#)
        let started = try item(#"{"id":"e2","kind":"episode","title":"Two","user_data":{"position_ms":60000}}"#)
        let watched = try item(#"{"id":"e3","kind":"episode","title":"Three","user_data":{"played":true}}"#)
        let film = try item(#"{"id":"m1","kind":"movie","title":"Heat"}"#)
        XCTAssertTrue(fresh.spoilerHidden(true))
        XCTAssertFalse(fresh.spoilerHidden(false))
        XCTAssertFalse(started.spoilerHidden(true))
        XCTAssertFalse(watched.spoilerHidden(true))
        XCTAssertFalse(film.spoilerHidden(true))
    }

    func testCardUsesTheShowsPictureElseBlursTheStill() throws {
        let withShow = MediaCard(item: try item(#"{"id":"e1","kind":"episode","title":"Pilot","images":{"primary":"/still","series_backdrop":"/show"}}"#))
        let safe = withShow.spoilerSafe(true)
        XCTAssertEqual(safe.thumb, "/show")
        XCTAssertFalse(safe.blurred)
        XCTAssertEqual(withShow.spoilerSafe(false).thumb, "/still")

        let stillOnly = MediaCard(item: try item(#"{"id":"e1","kind":"episode","title":"Pilot","images":{"primary":"/still"}}"#)).spoilerSafe(true)
        XCTAssertEqual(stillOnly.thumb, "/still")
        XCTAssertTrue(stillOnly.blurred)
    }
}
