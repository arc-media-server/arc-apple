import XCTest
@testable import ArcKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class WatchTogetherTests: XCTestCase {
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

    private let roomJSON = #"""
    {"id":"r1","revision":4,"generation":2,"state":"paused","position_ms":0,"at_ms":1000,"rate":1,
     "server_time_ms":1000,"host_id":"","host_name":"Jo","self_id":"p2","available":true,"item_id":"m1",
     "item":{"id":"m1","title":"Heat","kind":"movie"},
     "participants":[{"id":"p2","name":"Sam","available":true,"ready":true,"state":"paused"}],
     "invited":[{"name":"Alex"}],"future_field":true}
    """#

    func testInvitingPeopleAndTheRoomsList() async throws {
        answer(200, #"{"people":[{"id":"u2","name":"Sam","color":"blue","friend":false,"can_watch":true},{"id":"u3","name":"Kid","color":"teal","can_watch":false}]}"#)
        answer(201, #"{"room":{"id":"r1","state":"paused","created_at_ms":5,"host_name":"Jo","hosting":true,"joined":false,"item":{"id":"m1","title":"Heat","kind":"movie"},"participants":[],"invited":["Sam"]},"invite_code":"ABCD2345","invite_expires_at_ms":9}"#)
        answer(200, #"{"rooms":[{"id":"r1","state":"playing","host_name":"Jo","item":{"id":"m1","title":"Heat"},"participants":["Jo","Sam"]}]}"#)
        let people = try await api.watchPeople(itemId: "m 1")
        XCTAssertEqual(people.map(\.name), ["Sam", "Kid"])
        XCTAssertEqual(people.map(\.canWatch), [true, false])
        XCTAssertEqual(StubArc.requests[0].url?.absoluteString, "http://arc.test:8099/api/v1/watch-together/people?item_id=m%201")
        let created = try await api.createInvitedRoom(itemId: "m1", profileIds: ["u2"])
        XCTAssertTrue(created.room.hosting)
        XCTAssertEqual(created.room.invited, ["Sam"])
        // The server refuses unknown fields: nothing extra goes with the request.
        XCTAssertEqual(StubArc.bodies[1], #"{"item_id":"m1","profile_ids":["u2"]}"#)
        let rooms = try await api.watchRooms()
        XCTAssertEqual(rooms.first?.participants, ["Jo", "Sam"])
        XCTAssertTrue(rooms.first?.isPlaying ?? false)
        XCTAssertFalse(rooms.first?.hosting ?? true)
        XCTAssertEqual(rooms.first?.invited, [])
    }

    func testJoiningFromTheListAndTheRoomsFields() async throws {
        answer(200, roomJSON)
        let room = try await api.acceptRoom("r1")
        XCTAssertEqual(StubArc.requests[0].url?.path, "/api/v1/watch-together/rooms/r1/join")
        XCTAssertEqual(StubArc.requests[0].httpMethod, "POST")
        XCTAssertEqual(room.positionMs, 0)
        XCTAssertEqual(room.invited.map(\.name), ["Alex"])
        // Nobody holds the room until its creator comes: the guest waits for "Jo".
        XCTAssertFalse(room.isHost)
        XCTAssertEqual(room.hostDisplayName, "Jo")
        XCTAssertEqual(room.item?.title, "Heat")
    }

    func testACommandOnAChangedRoomHandsBackTheRoom() async throws {
        answer(409, #"{"error":"room changed","room":\#(roomJSON)}"#)
        do {
            _ = try await api.roomCommand("r1", revision: 3, action: "seek", positionMs: -5)
            XCTFail("expected a conflict")
        } catch let conflict as RoomConflict {
            XCTAssertEqual(conflict.room.revision, 4)
        }
        XCTAssertEqual(StubArc.bodies[0], #"{"action":"seek","position_ms":0,"revision":3}"#)
        answer(200, roomJSON)
        _ = try await api.roomHeartbeat("r1", generation: 2, positionMs: 1500, state: "playing", ready: true)
        XCTAssertEqual(StubArc.bodies[1], #"{"generation":2,"position_ms":1500,"ready":true,"state":"playing"}"#)
    }

    func testCurrentRoomIsNilWhenThereIsNone() async throws {
        answer(404, #"{"error":"room or playable invitation not found"}"#)
        let none = try await api.currentRoom()
        XCTAssertNil(none)
    }

    func testCodes() {
        XCTAssertEqual(WatchCode.normalize(" abcd-23 45 "), "ABCD2345")
        XCTAssertEqual(WatchCode.format("abcd2345"), "ABCD-2345")
        XCTAssertEqual(WatchCode.format("abc"), "ABC")
    }

    func testTheShortestRoundTripSetsTheClock() {
        XCTAssertNil(WatchSync.clockOffset([]))
        // Server 500 ms ahead; the slow sample (asymmetric delays) is ignored.
        let fast = ClockSample(c0: 1000, c3: 1040, s1: 1520, s2: 1520)
        let slow = ClockSample(c0: 2000, c3: 2600, s1: 2550, s2: 2550)
        XCTAssertEqual(WatchSync.clockOffset([slow, fast]), 500)
    }

    func testWhereTheRoomShouldBe() throws {
        var room = try ArcJSON.decoder.decode(WatchRoom.self, from: Data(roomJSON.utf8))
        XCTAssertEqual(WatchSync.expectedPosition(room, serverNowMs: 9000), 0, "paused stays put")
        room = try ArcJSON.decoder.decode(WatchRoom.self, from: Data(roomJSON.replacingOccurrences(of: #""state":"paused","position_ms":0"#, with: #""state":"playing","position_ms":5000"#).utf8))
        XCTAssertEqual(WatchSync.expectedPosition(room, serverNowMs: 3000), 7000)
        XCTAssertEqual(WatchSync.expectedPosition(room, serverNowMs: 500), 5000, "never behind the last report")
    }

    func testDriftCorrection() {
        XCTAssertEqual(WatchSync.correction(localMs: 10_300, expectedMs: 10_000), WatchSync.Correction.none)
        XCTAssertEqual(WatchSync.correction(localMs: 12_000, expectedMs: 10_000), .rate(0.97))
        XCTAssertEqual(WatchSync.correction(localMs: 8_000, expectedMs: 10_000), .rate(1.03))
        XCTAssertEqual(WatchSync.correction(localMs: 20_000, expectedMs: 10_000), .seek(toMs: 10_000))
        // A player that can't change speed jumps past 1.5 s instead.
        XCTAssertEqual(WatchSync.correction(localMs: 11_000, expectedMs: 10_000, canChangeRate: false), WatchSync.Correction.none)
        XCTAssertEqual(WatchSync.correction(localMs: 12_000, expectedMs: 10_000, canChangeRate: false), .seek(toMs: 10_000))
    }

    func testOnlyNewerRoomsAreTaken() throws {
        let room = try ArcJSON.decoder.decode(WatchRoom.self, from: Data(roomJSON.utf8))
        let older = try ArcJSON.decoder.decode(WatchRoom.self, from: Data(roomJSON.replacingOccurrences(of: #""revision":4"#, with: #""revision":3"#).utf8))
        XCTAssertTrue(WatchSync.shouldAdopt(room, over: nil))
        XCTAssertTrue(WatchSync.shouldAdopt(room, over: older))
        XCTAssertFalse(WatchSync.shouldAdopt(older, over: room))
    }

    func testTheRoomStreamsEvents() {
        var parser = SSEParser()
        XCTAssertNil(parser.feed(": keep-alive"))
        XCTAssertNil(parser.feed("id: 7"))
        XCTAssertNil(parser.feed("event: room"))
        XCTAssertNil(parser.feed(#"data: {"id":"r1"}"#))
        XCTAssertEqual(parser.feed(""), SSEParser.Event(name: "room", data: #"{"id":"r1"}"#, id: "7"))
        XCTAssertNil(parser.feed(""), "a blank line alone is no event")
        let request = api.roomEventsRequest("r/1")
        XCTAssertEqual(request?.url?.absoluteString, "http://arc.test:8099/api/v1/watch-together/r%2F1/events")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer t0k")
    }
}
