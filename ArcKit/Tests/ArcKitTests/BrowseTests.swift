import XCTest
@testable import ArcKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Browsing past Home: what's asked for, and answers read as Arc sends them.
final class BrowseTests: XCTestCase {
    private var api: ArcAPI!

    override func setUp() {
        StubArc.answers = []
        StubArc.requests = []
        StubArc.bodies = []
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubArc.self]
        api = ArcAPI(baseURL: URL(string: "http://arc.test:8099")!, session: URLSession(configuration: config), token: { "t0k" })
    }

    private func answer(_ status: Int, _ body: String = "{}") { StubArc.answers.append(.init(status: status, body: body)) }

    func testALibraryGridsSortAndFiltersBecomeItemsParameters() {
        let movies = Library(id: 3, name: "Films", kind: "movies")
        var q = LibraryQuery()
        XCTAssertFalse(q.filtered)
        XCTAssertEqual(q.parameters(library: movies, offset: 0, limit: 60),
                       ["library_id": "3", "kind": "movie", "sort": "title", "offset": "0", "limit": "60"])
        q.sort = .lastPlayed
        q.reversed = true
        q.unwatchedOnly = true
        q.genre = "Drama"
        q.decade = "1990"
        q.resolution = "4k"
        XCTAssertTrue(q.filtered)
        let shows = Library(id: 4, name: "TV", kind: "shows")
        XCTAssertEqual(q.parameters(library: shows, offset: 60, limit: 60),
                       ["library_id": "4", "kind": "series", "sort": "watched", "reverse": "1", "unwatched": "1",
                        "genre": "Drama", "decade": "1990", "resolution": "4k", "offset": "60", "limit": "60"])
    }

    func testTheLetterCountsAreAskedForOnlyWhenSortedByTitle() {
        let films = Library(id: 3, name: "Films", kind: "movies")
        var q = LibraryQuery()
        XCTAssertTrue(q.showsLetters)
        XCTAssertEqual(q.parameters(library: films, offset: 0, limit: 60, letters: true)["letters"], "1")
        XCTAssertNil(q.parameters(library: films, offset: 0, limit: 60)["letters"])
        q.sort = .added
        XCTAssertFalse(q.showsLetters)
        XCTAssertNil(q.parameters(library: films, offset: 0, limit: 60, letters: true)["letters"])
    }

    func testAPageReadsItsLetterCounts() async throws {
        answer(200, ##"{"total":5,"offset":0,"items":[{"id":"m1","kind":"movie","title":"007"}],"letters":[{"letter":"#","count":2},{"letter":"a","count":3}]}"##)
        let page = try await api.items(["library_id": "3", "letters": "1"])
        XCTAssertEqual(page.letters, [LetterCount(letter: "#", count: 2), LetterCount(letter: "a", count: 3)])
        XCTAssertTrue(StubArc.requests[0].url?.query?.contains("letters=1") == true)
        // Without letters=1 there are none.
        let plain = try ArcJSON.decoder.decode(ItemPage.self, from: Data(#"{"total":0,"items":[]}"#.utf8))
        XCTAssertTrue(plain.letters.isEmpty)
    }

    func testEachLetterJumpsToItsFirstTitle() {
        // As the server sends them: digits first, other scripts last, both as "#".
        let letters = [LetterCount(letter: "#", count: 2), LetterCount(letter: "a", count: 2), LetterCount(letter: "s", count: 1),
                       LetterCount(letter: "z", count: 1), LetterCount(letter: "#", count: 2), LetterCount(letter: "b", count: 0)]
        XCTAssertEqual(letterJumps(letters, reversed: false).map { "\($0.letter)\($0.offset)" }, ["#0", "A2", "S4", "Z5"])
        // Z to A: the list starts with the other scripts.
        XCTAssertEqual(letterJumps(letters, reversed: true).map { "\($0.letter)\($0.offset)" }, ["#0", "Z2", "S3", "A4"])
        XCTAssertTrue(letterJumps([], reversed: false).isEmpty)
    }

    func testAJumpLoadsThroughTheLetterAndAPageMore() {
        func pages(_ target: Int, have: Int, total: Int) -> [String] {
            pagesToReach(target, have: have, total: total, page: 60).map { "\($0.offset)+\($0.limit)" }
        }
        XCTAssertEqual(pages(1_200, have: 60, total: 3_000), ["60+500", "560+500", "1060+200"])
        XCTAssertEqual(pages(2_990, have: 60, total: 3_000), ["60+500", "560+500", "1060+500", "1560+500", "2060+500", "2560+440"])
        // Already loaded: nothing to ask for.
        XCTAssertEqual(pages(10, have: 120, total: 3_000), [])
    }

    func testSearchReadsEveryKindOfResult() async throws {
        answer(200, #"{"movies":[{"id":"m1","kind":"movie","title":"Alien"}],"shows":[],"collections":[{"id":"c1","title":"Alien Collection","count":4}],"people":[{"id":7,"name":"Sigourney Weaver","known_for":"Alien","image":"/api/people/7/image?v=1"}]}"#)
        let found = try await api.search("ali en")
        XCTAssertEqual(StubArc.requests[0].url?.absoluteString, "http://arc.test:8099/api/v1/search?q=ali%20en")
        XCTAssertEqual(found.movies.map(\.title), ["Alien"])
        XCTAssertTrue(found.episodes.isEmpty)
        XCTAssertEqual(found.collections.first?.count, 4)
        XCTAssertEqual(found.people.first?.knownFor, "Alien")
        XCTAssertFalse(found.isEmpty)
    }

    func testATitlesPageCarriesItsCastAndCollections() throws {
        let json = #"{"id":"m1","kind":"movie","title":"Alien","credits":[{"person_id":7,"name":"Sigourney Weaver","role":"actor","character":"Ripley"},{"person_id":8,"name":"Ridley Scott","role":"director"}],"collections":[{"id":"c1","title":"Alien Collection","kind":"tmdb"}]}"#
        let item = try ArcJSON.decoder.decode(Item.self, from: Data(json.utf8))
        XCTAssertEqual(item.credits.map(\.name), ["Sigourney Weaver", "Ridley Scott"])
        XCTAssertEqual(item.credits[0].character, "Ripley")
        XCTAssertNotEqual(item.credits[0].id, item.credits[1].id)
        XCTAssertEqual(item.collections.first?.title, "Alien Collection")
    }

    func testFoldersPeopleFacetsAndPlaylists() async throws {
        answer(200, #"{"path":"Home","folders":[{"name":"2019","path":"Home/2019","count":12,"cover":"/api/items/v1/images/primary"}],"items":[{"id":"v1","kind":"movie","title":"Beach"}],"trail":[]}"#)
        answer(200, #"{"person":{"id":7,"name":"Sigourney Weaver","count":1},"credits":[{"item":{"id":"m1","kind":"movie","title":"Alien"},"roles":["actor"],"character":"Ripley"}]}"#)
        answer(200, #"{"genres":[{"value":"Drama","count":3}],"decades":[{"value":"1990","count":2}],"resolutions":[],"languages":[]}"#)
        answer(200, #"[{"id":"p1","title":"Friday","count":2,"images":["/api/items/m1/images/primary"]}]"#)
        let page = try await api.folders(libraryId: 5, path: "Home")
        XCTAssertEqual(page.folders.first?.count, 12)
        XCTAssertEqual(page.items.first?.title, "Beach")
        XCTAssertEqual(StubArc.requests[0].url?.absoluteString, "http://arc.test:8099/api/v1/libraries/5/folders?path=Home")
        let person = try await api.person(7)
        XCTAssertEqual(person.credits.first?.character, "Ripley")
        let facets = try await api.facets(libraryId: 3)
        XCTAssertEqual(facets.genres.first?.count, 3)
        XCTAssertEqual(facets.decades.first?.value, "1990")
        let playlists = try await api.playlists()
        XCTAssertEqual(playlists.first?.images.count, 1)
    }

    func testCardActionsAndPreferencesSendJSON() async throws {
        answer(204, "")
        answer(204, "")
        answer(200, #"{"auto_play":false,"subtitle_mode":"always"}"#)
        try await api.setPlayed("m 1", true)
        try await api.setWatchlisted("m1", false)
        let prefs = try await api.updatePrefs(["auto_play": .bool(false)])
        XCTAssertEqual(StubArc.requests.map(\.httpMethod), ["PUT", "PUT", "PATCH"])
        XCTAssertEqual(StubArc.requests[0].url?.path, "/api/v1/items/m 1/played")
        XCTAssertEqual(StubArc.bodies, [#"{"played":true}"#, #"{"on":false}"#, #"{"auto_play":false}"#])
        XCTAssertFalse(prefs.autoPlay)
        XCTAssertEqual(prefs.subtitleMode, "always")
    }

    func testASeasonIsMarkedWatchedByItsNumber() async throws {
        answer(204, "")
        answer(204, "")
        try await api.setPlayed(seriesId: "s 1", seasonNumber: 2, true)
        try await api.setPlayed(seriesId: "s1", seasonNumber: 0, false)
        XCTAssertEqual(StubArc.requests.map(\.httpMethod), ["PUT", "PUT"])
        XCTAssertEqual(StubArc.requests[0].url?.path, "/api/v1/items/s 1/played")
        // A whole number, as Arc reads season_number.
        XCTAssertEqual(StubArc.bodies, [#"{"played":true,"season_number":2}"#, #"{"played":false,"season_number":0}"#])
    }

    func testRemovingFromContinueWatchingDeletesItsEntry() async throws {
        answer(204, "")
        try await api.removeFromContinue("e/7")
        XCTAssertEqual(StubArc.requests.map(\.httpMethod), ["DELETE"])
        XCTAssertEqual(StubArc.requests[0].url?.absoluteString, "http://arc.test:8099/api/v1/home/continue/e%2F7")
    }

    func testRemovingFromContinueWatchingCanBeRefused() async {
        answer(404, #"{"error":"item not found"}"#)
        do {
            try await api.removeFromContinue("gone")
            XCTFail("expected a failure")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 404)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testASeasonIsWatchedWhenEveryEpisodeOutIs() throws {
        func season(_ episodes: String) throws -> Season {
            try ArcJSON.decoder.decode(Season.self, from: Data(#"{"season_number":1,"episodes":[\#(episodes)]}"#.utf8))
        }
        let seen = #"{"id":"e1","kind":"episode","title":"One","user_data":{"played":true}}"#
        let unseen = #"{"id":"e2","kind":"episode","title":"Two"}"#
        let upcoming = #"{"id":"e3","kind":"episode","title":"Three","available":false}"#
        XCTAssertTrue(try season(seen + "," + upcoming).watched)
        XCTAssertFalse(try season(seen + "," + unseen).watched)
        XCTAssertTrue(try season(seen).markable)
        let notOut = try season(upcoming)
        XCTAssertFalse(notOut.watched)
        XCTAssertFalse(notOut.markable)
        XCTAssertFalse(try season("").markable)
    }

    func testARefusedActionIsAnError() async {
        answer(404, #"{"error":"item not found"}"#)
        do {
            try await api.setPlayed("gone", true)
            XCTFail("expected a failure")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 404)
            XCTAssertEqual(error.message, "item not found")
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}
