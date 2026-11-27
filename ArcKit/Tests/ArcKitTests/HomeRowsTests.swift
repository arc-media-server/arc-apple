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

    func testTheSameSeasonAddedOnTwoDaysIsTwoCardsWithTheirOwnIDs() throws {
        // A row's cards need distinct ids; two days' batches of one season are separate cards.
        let json = #"[{"type":"season","item":{"id":"s1","kind":"series","title":"Firefly"},"season_number":2,"episodes":3,"added_at":1700000000},"#
            + #"{"type":"season","item":{"id":"s1","kind":"series","title":"Firefly"},"season_number":2,"episodes":4,"added_at":1700172800}]"#
        let cards = try ArcJSON.decoder.decode([RecentCard].self, from: Data(json.utf8)).map { MediaCard(recent: $0) }
        XCTAssertNotEqual(cards[0].id, cards[1].id)
    }

    func testRecentlyAddedCardsCarryTheirNewEpisodes() throws {
        // A season's batch: its number and the count (the corner badge). A whole show's: the count
        // (its caption). A single episode: neither.
        let json = #"[{"type":"season","item":{"id":"s1","kind":"series","title":"Firefly"},"season_number":2,"episodes":3,"added_at":1},"#
            + #"{"type":"series","item":{"id":"s2","kind":"series","title":"Severance"},"episodes":5,"added_at":2},"#
            + #"{"type":"episode","item":{"id":"e1","kind":"episode","title":"Pilot"},"added_at":3}]"#
        let cards = try ArcJSON.decoder.decode([RecentCard].self, from: Data(json.utf8)).map { MediaCard(recent: $0) }
        XCTAssertEqual(cards.map(\.seasonNumber), [2, nil, nil])
        XCTAssertEqual(cards.map(\.newEpisodes), [3, 5, 0])
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
        // Continue Watching shows the show's own picture.
        XCTAssertEqual(card.withShowArt().art(.thumb, seasonPosters: false), "/bg")
        XCTAssertTrue(card.withShowArt().showArt)
        let film = MediaCard(item: Item(id: "m1", kind: "movie", title: "Heat", images: Images(primary: "/p", backdrop: "/b")))
        XCTAssertEqual(film.withShowArt().art(.thumb, seasonPosters: false), "/b")
    }

    func testAnEpisodeNotOutYetSaysWhenItReleases() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let today = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 7)))
        var ep = Item(id: "e2", kind: "episode", title: "Young Blood")
        ep.releaseDate = "2026-11-08"
        ep.available = false
        XCTAssertEqual(ep.upcomingRelease(asOf: today, calendar: cal), cal.date(from: DateComponents(year: 2026, month: 11, day: 8)))
        ep.releaseDate = "2026-11-07" // out today
        XCTAssertNil(ep.upcomingRelease(asOf: today, calendar: cal))
        ep.releaseDate = "2026-11-08"
        ep.available = true // already on the server
        XCTAssertNil(ep.upcomingRelease(asOf: today, calendar: cal))
        // Within the week, the weekday; further out, the date.
        let en = Locale(identifier: "en_GB")
        let thursday = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 12)))
        XCTAssertEqual(Item.releaseDay(thursday, asOf: today, calendar: cal, locale: en), "Thursday")
        let later = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 19)))
        XCTAssertEqual(Item.releaseDay(later, asOf: today, calendar: cal, locale: en), "19 Nov")
    }
}
