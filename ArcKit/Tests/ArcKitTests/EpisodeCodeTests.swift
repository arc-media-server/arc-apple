import XCTest
@testable import ArcKit

final class EpisodeCodeTests: XCTestCase {
    private func item(_ json: String) throws -> Item { try ArcJSON.decoder.decode(Item.self, from: Data(json.utf8)) }

    func testNumberedSpecialAndUnplaced() throws {
        let episode = try item(#"{"id":"e1","kind":"episode","title":"Pilot","season_number":1,"episode_number":4}"#)
        let special = try item(#"{"id":"e2","kind":"episode","title":"Extra","season_number":0,"episode_number":3}"#)
        let unplaced = try item(#"{"id":"e3","kind":"episode","title":"Lost","season_number":0,"episode_number":0}"#)
        let film = try item(#"{"id":"m1","kind":"movie","title":"Heat"}"#)
        XCTAssertEqual(episode.episodeCode, .numbered(season: 1, episode: 4))
        XCTAssertEqual(special.episodeCode, .special(3))
        XCTAssertNil(unplaced.episodeCode)
        XCTAssertNil(film.episodeCode)
    }
}
