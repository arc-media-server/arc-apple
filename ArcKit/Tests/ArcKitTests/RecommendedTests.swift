import XCTest
@testable import ArcKit

/// A library's Recommended rows read with their defaults and are titled as the web titles them.
final class RecommendedTests: XCTestCase {
    func testRowsReadWithTheirDefaults() throws {
        let json = #"{"rows":[{"id":"r1","type":"because_you_watched","title":"Because you watched Heat","name":"Heat","items":[{"id":"a","kind":"movie","title":"Ronin"}],"has_more":true,"items_url":"/x"},{"id":"r2","type":"later_kind"}]}"#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let page = try decoder.decode(RecommendedPage.self, from: Data(json.utf8))
        XCTAssertEqual(page.rows.count, 2)
        XCTAssertEqual(page.rows[0].items.first?.title, "Ronin")
        XCTAssertEqual(page.rows[1].items.count, 0)
        XCTAssertEqual(page.rows[1].title, "")
        XCTAssertEqual(page.rows[1].style, "")
    }

    func testTitlesFollowTheWeb() {
        func title(_ type: String, name: String? = nil, role: String? = nil, kind: String = "movies") -> RecommendedTitle {
            recommendedTitle(RecommendedRow(id: "x", type: type, title: "Arc's", name: name, role: role), libraryName: "Films", libraryKind: kind)
        }
        XCTAssertEqual(title("recently_added"), .key("rec.recently_added", "Films"))
        XCTAssertEqual(title("because_you_watched", name: "Heat"), .key("rec.because_you_watched", "Heat"))
        XCTAssertEqual(title("top_rated", kind: "shows"), .key("rec.top_rated_shows", nil))
        XCTAssertEqual(title("recently_watched", kind: "shows"), .key("rec.recently_watched_episodes", nil))
        XCTAssertEqual(title("top_by_person", name: "Michael Mann", role: "director"), .key("rec.top_movies_by", "Michael Mann"))
        XCTAssertEqual(title("top_by_person", name: "Al Pacino", role: "actor"), .key("rec.top_movies_with", "Al Pacino"))
        XCTAssertEqual(title("something_new"), .server("Arc's"))
    }
}
