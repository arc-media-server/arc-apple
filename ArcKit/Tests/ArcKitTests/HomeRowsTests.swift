import XCTest
@testable import ArcKit

final class HomeRowsTests: XCTestCase {
    private let movies = Library(id: 1, name: "Movies", kind: "movies")
    private let shows = Library(id: 2, name: "TV", kind: "shows")
    private let videos = Library(id: 3, name: "Home", kind: "videos")
    private let june = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 6, day: 1).date!

    func testRowsFollowTheLibraryOrderWithTheWatchlistInItsPlace() {
        var prefs = Prefs(home: [
            HomeRowPref(id: "custom:a", title: "Short films", filter: ["library_id": .number(1), "max_runtime": .number(40)]),
            HomeRowPref(id: "recent:2", hidden: true),
            HomeRowPref(id: "collection:c9", title: "Bond"),
        ], watchlistPosition: 1)
        prefs.splitUpNext = true
        let rows = resolveHomeRows(prefs: prefs, libraries: [movies, shows, videos], today: june)
        XCTAssertEqual(rows.map(\.id), ["continue", "next-up", "recent:1", "custom:a", "watchlist", "recent:3", "collection:c9"])
        XCTAssertEqual(rows.first?.source, .continueWatching(withUpNext: false))
        XCTAssertEqual(rows.first { $0.id == "recent:3" }?.style, .thumb)
    }

    func testTheWatchlistCanComeLastAndSeasonsAddTheirRow() {
        let halloween = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 10, day: 31).date!
        let rows = resolveHomeRows(prefs: Prefs(watchlistPosition: 9), libraries: [movies], today: halloween)
        XCTAssertEqual(rows.map(\.id), ["continue", "seasonal", "recent:1", "watchlist"])
        XCTAssertEqual(rows[1].source, .seasonal(.horror))
        XCTAssertNil(SeasonalPick.on(june))
    }

    func testLibrariesInTheProfilesOrderWithNewOnesLast() {
        XCTAssertEqual(orderedLibraries([movies, shows, videos], order: [3, 1]).map(\.id), [3, 1, 2])
    }

    func testACustomRowsFilterBecomesItsQuery() {
        let q = customRowQuery(filter: ["library_id": .number(2), "genre": .string("Drama"), "unwatched": .bool(true), "decade": .number(0), "x": .string("y")], library: shows)
        XCTAssertEqual(q, ["library_id": "2", "genre": "Drama", "unwatched": "1", "kind": "series", "limit": "24"])
    }

    func testCardsChooseArtworkAsTheWebDoes() {
        let ep = Item(id: "e1", kind: "episode", title: "Pilot", images: Images(primary: "/still", seriesPrimary: "/show", seriesBackdrop: "/bg", seasonPrimary: "/s1"))
        let card = MediaCard(item: ep)
        XCTAssertEqual(card.art(.poster, seasonPosters: false), "/show")
        XCTAssertEqual(card.art(.poster, seasonPosters: true), "/s1")
        XCTAssertEqual(card.art(.thumb, seasonPosters: false), "/still")
        XCTAssertEqual(card.art(.backdrop, seasonPosters: false), "/bg")
    }
}
