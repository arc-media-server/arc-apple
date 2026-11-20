import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Watch Together (the server's docs/WATCH-TOGETHER-API.md): a room shares one timeline (title,
// position, playing or paused); everyone streams their own copy. This file has the models, the
// calls and the maths; the app keeps the live connection (RoomSession in ArcTV).

/// Someone in a room.
public struct WatchParticipant: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    @Default<Defaults.False> public var available: Bool
    @Default<Defaults.False> public var ready: Bool
    /// playing, paused or waiting (loading).
    @Default<Defaults.Empty> public var state: String
}

public struct WatchItemSummary: Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    @Default<Defaults.Empty> public var kind: String
}

public struct WatchInvited: Codable, Sendable, Equatable {
    public let name: String
}

/// A room as this device sees it (personalized: `selfId`, `available`).
public struct WatchRoom: Codable, Sendable, Equatable {
    public let id: String
    public let revision: Int64
    /// Bumps on every seek or title change: heartbeats name the one they've loaded.
    public let generation: Int64
    /// paused, playing, waiting (for someone loading) or ended.
    public let state: String
    /// In the file, at server time `atMs`.
    public let positionMs: Int64
    public let atMs: Int64
    @Default<Defaults.ZeroDouble> public var rate: Double
    @Default<Defaults.Zero64> public var serverTimeMs: Int64
    public var waitUntilMs: Int64?
    @Default<Defaults.Empty> public var hostId: String
    /// Who made the room (its host when present).
    public var hostName: String?
    @Default<Defaults.Empty> public var selfId: String
    public var changedBy: String?
    /// False when this profile may not play the room's current title.
    @Default<Defaults.False> public var available: Bool
    public var itemId: String?
    public var item: WatchItemSummary?
    @Default<Defaults.List<WatchParticipant>> public var participants: [WatchParticipant]
    @Default<Defaults.List<WatchInvited>> public var invited: [WatchInvited]

    public var isHost: Bool { !selfId.isEmpty && selfId == hostId }

    /// The host's name: from the people here, else who made the room.
    public var hostDisplayName: String {
        participants.first { $0.id == hostId }?.name ?? hostName ?? ""
    }
}

/// A room with its code, for the device that made it (or renewed the code).
public struct WatchInvite: Codable, Sendable, Equatable {
    public let room: WatchRoom
    public let inviteCode: String
    public let inviteExpiresAtMs: Int64
}

/// Someone this profile may invite.
public struct WatchPerson: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    @Default<Defaults.Empty> public var color: String
    @Default<Defaults.False> public var friend: Bool
    /// Whether they may play the title asked about.
    @Default<Defaults.True> public var canWatch: Bool
}

/// A room in this profile's list (Home's Watch Together row).
public struct ListedRoom: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    @Default<Defaults.Empty> public var state: String
    @Default<Defaults.Zero64> public var positionMs: Int64
    @Default<Defaults.Zero64> public var createdAtMs: Int64
    @Default<Defaults.Empty> public var hostName: String
    /// This profile made it.
    @Default<Defaults.False> public var hosting: Bool
    /// This device and profile are in it.
    @Default<Defaults.False> public var joined: Bool
    public let item: WatchItemSummary
    @Default<Defaults.List<String>> public var participants: [String]
    @Default<Defaults.List<String>> public var invited: [String]

    /// "Watching now" while it plays.
    public var isPlaying: Bool { state == "playing" || state == "waiting" }
}

public struct CreatedRoom: Codable, Sendable, Equatable {
    public let room: ListedRoom
    public let inviteCode: String
    public let inviteExpiresAtMs: Int64
}

public struct ServerTime: Codable, Sendable, Equatable {
    public let clientSentMs: Int64
    public let serverReceivedMs: Int64
    public let serverSentMs: Int64
}

/// The room changed since the revision a command named (409): adopt `room`, then retry if the
/// action still makes sense.
public struct RoomConflict: Error, Sendable {
    public let room: WatchRoom
}

private struct PeopleAnswer: Decodable { @Default<Defaults.List<WatchPerson>> var people: [WatchPerson] }
private struct RoomsAnswer: Decodable { @Default<Defaults.List<ListedRoom>> var rooms: [ListedRoom] }
private struct ConflictAnswer: Decodable { let room: WatchRoom }

private struct CommandBody: Encodable {
    let revision: Int64
    let action: String
    let positionMs: Int64?
    let itemId: String?
}

private struct HeartbeatBody: Encodable {
    let generation: Int64
    let positionMs: Int64
    let state: String
    let ready: Bool
}

private struct CreateBody: Encodable {
    let itemId: String
    let startMs: Int64?
    let profileIds: [String]?
}

private struct RevisionBody: Encodable { let revision: Int64 }
private struct CodeBody: Encodable { let code: String }
private struct PeopleBody: Encodable { let profileIds: [String] }

extension ArcAPI {
    /// Who this profile may invite; with `itemId`, each says whether they may play it.
    public func watchPeople(itemId: String? = nil) async throws -> [WatchPerson] {
        let path = itemId.map { "watch-together/people?item_id=\(enc($0))" } ?? "watch-together/people"
        let answer: PeopleAnswer = try await get(path, route: "watch-together/people")
        return answer.people
    }

    /// The rooms this profile made, was invited to or is in, newest first.
    public func watchRooms() async throws -> [ListedRoom] {
        let answer: RoomsAnswer = try await get("watch-together/rooms")
        return answer.rooms
    }

    /// A room for chosen people: nobody is in it until they join from their lists.
    public func createInvitedRoom(itemId: String, profileIds: [String]) async throws -> CreatedRoom {
        try await sendJSON("POST", "watch-together/rooms", CreateBody(itemId: itemId, startMs: nil, profileIds: profileIds))
    }

    /// A room with a code, joined straight away by this device.
    public func createRoom(itemId: String) async throws -> WatchInvite {
        try await sendJSON("POST", "watch-together", CreateBody(itemId: itemId, startMs: 0, profileIds: nil))
    }

    public func joinRoom(code: String) async throws -> WatchRoom {
        try await sendJSON("POST", "watch-together/join", CodeBody(code: WatchCode.normalize(code)))
    }

    /// Joins a room from this profile's list, without a code.
    public func acceptRoom(_ id: String) async throws -> WatchRoom {
        try await sendJSON("POST", "watch-together/rooms/\(enc(id))/join", Empty(), route: "watch-together/rooms/{id}/join")
    }

    /// Declines an invitation, or cancels a room this profile made.
    public func dismissRoom(_ id: String) async throws {
        let route = "watch-together/rooms/{id}/dismiss"
        let (status, data) = try await raw("POST", "watch-together/rooms/\(enc(id))/dismiss", route: route)
        guard (200...299).contains(status) else { throw failure(status, data, route) }
    }

    /// This device and profile's own room, or nil.
    public func currentRoom() async throws -> WatchRoom? {
        let route = "watch-together/current"
        let (status, data) = try await raw("GET", route, route: route)
        if status == 404 { return nil }
        guard (200...299).contains(status) else { throw failure(status, data, route) }
        return try decode(WatchRoom.self, data, route)
    }

    public func room(_ id: String) async throws -> WatchRoom {
        try await get("watch-together/\(enc(id))", route: "watch-together/{id}")
    }

    /// play, pause, seek (positionMs), change_item (itemId, positionMs) or end. A changed room
    /// throws `RoomConflict` with the room as it is now.
    public func roomCommand(_ id: String, revision: Int64, action: String, positionMs: Int64? = nil, itemId: String? = nil) async throws -> WatchRoom {
        try await roomCall("watch-together/\(enc(id))/commands", route: "watch-together/{id}/commands",
                           CommandBody(revision: revision, action: action, positionMs: positionMs.map { max(0, $0) }, itemId: itemId))
    }

    /// Reports this player every couple of seconds. A seek or new title since `generation`
    /// throws `RoomConflict`.
    public func roomHeartbeat(_ id: String, generation: Int64, positionMs: Int64, state: String, ready: Bool) async throws -> WatchRoom {
        try await roomCall("watch-together/\(enc(id))/heartbeat", route: "watch-together/{id}/heartbeat",
                           HeartbeatBody(generation: generation, positionMs: max(0, positionMs), state: state, ready: ready))
    }

    public func leaveRoom(_ id: String) async {
        _ = try? await raw("POST", "watch-together/\(enc(id))/leave", route: "watch-together/{id}/leave")
    }

    /// A new code for the room (host only).
    public func renewRoomCode(_ id: String, revision: Int64) async throws -> WatchInvite {
        let route = "watch-together/{id}/invite"
        let (status, data) = try await raw("POST", "watch-together/\(enc(id))/invite", body: try ArcJSON.encoder.encode(RevisionBody(revision: revision)), route: route)
        if status == 409, let conflict = try? ArcJSON.decoder.decode(ConflictAnswer.self, from: data) { throw RoomConflict(room: conflict.room) }
        guard (200...299).contains(status) else { throw failure(status, data, route) }
        return try decode(WatchInvite.self, data, route)
    }

    /// Invites more people to the room (host only).
    public func invitePeople(_ id: String, profileIds: [String]) async throws -> WatchRoom {
        try await sendJSON("POST", "watch-together/\(enc(id))/people", PeopleBody(profileIds: profileIds), route: "watch-together/{id}/people")
    }

    public func serverTime(clientSentMs: Int64) async throws -> ServerTime {
        try await get("watch-together/time?client_sent_ms=\(clientSentMs)", route: "watch-together/time")
    }

    /// The room's live stream (Server-Sent Events, event "room" with the whole room each time).
    public func roomEventsRequest(_ id: String) -> URLRequest? {
        guard let url = URL(string: baseString + "/api/v1/watch-together/\(enc(id))/events") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        for (k, v) in authorization { request.setValue(v, forHTTPHeaderField: k) }
        request.timeoutInterval = 3600
        return request
    }

    // MARK: - plumbing

    private struct Empty: Encodable {}

    private var baseString: String {
        var s = baseURL.absoluteString
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    func sendJSON<B: Encodable, T: Decodable>(_ method: String, _ path: String, _ body: B, route: String? = nil) async throws -> T {
        let route = route ?? path
        let (status, data) = try await raw(method, path, body: try ArcJSON.encoder.encode(body), route: route)
        guard (200...299).contains(status) else { throw failure(status, data, route) }
        return try decode(T.self, data, route)
    }

    private func roomCall<B: Encodable>(_ path: String, route: String, _ body: B) async throws -> WatchRoom {
        let (status, data) = try await raw("POST", path, body: try ArcJSON.encoder.encode(body), route: route)
        if status == 409, let conflict = try? ArcJSON.decoder.decode(ConflictAnswer.self, from: data) {
            throw RoomConflict(room: conflict.room)
        }
        guard (200...299).contains(status) else { throw failure(status, data, route) }
        return try decode(WatchRoom.self, data, route)
    }
}

/// Room codes: eight letters and digits, read aloud as XXXX-XXXX.
public enum WatchCode {
    public static func normalize(_ input: String) -> String {
        String(input.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) })
    }

    public static func format(_ code: String) -> String {
        let c = normalize(code)
        guard c.count == 8 else { return c }
        return "\(c.prefix(4))-\(c.suffix(4))"
    }
}

/// One `/time` sample: client send and receive, server receive and send (epoch ms).
public struct ClockSample: Sendable, Equatable {
    public let c0, c3, s1, s2: Int64
    public init(c0: Int64, c3: Int64, s1: Int64, s2: Int64) { self.c0 = c0; self.c3 = c3; self.s1 = s1; self.s2 = s2 }
}

public enum WatchSync {
    /// How far the server's clock is ahead of this one, from the sample with the shortest round
    /// trip (NTP's midpoint estimate). Nil with no samples.
    public static func clockOffset(_ samples: [ClockSample]) -> Double? {
        var best: (rtt: Int64, offset: Double)?
        for s in samples {
            let rtt = s.c3 - s.c0 - (s.s2 - s.s1)
            let offset = Double((s.s1 - s.c0) + (s.s2 - s.c3)) / 2
            if best == nil || rtt < best!.rtt { best = (rtt, offset) }
        }
        return best?.offset
    }

    /// Where the room should be in the file at server time `serverNowMs`.
    public static func expectedPosition(_ room: WatchRoom, serverNowMs: Double) -> Double {
        guard room.state == "playing" else { return Double(room.positionMs) }
        let rate = room.rate > 0 ? room.rate : 1
        return Double(room.positionMs) + max(0, serverNowMs - Double(room.atMs)) * rate
    }

    public enum Correction: Equatable, Sendable {
        case none
        case rate(Double)
        case seek(toMs: Double)
    }

    /// How to bring a player back in step: under half a second, leave it; up to three seconds,
    /// play slightly slower or faster until caught up; beyond that, jump. A player that can't
    /// change speed (`canChangeRate` false) jumps once it's more than 1.5 s out.
    public static func correction(localMs: Double, expectedMs: Double, canChangeRate: Bool = true) -> Correction {
        let drift = localMs - expectedMs
        let size = abs(drift)
        if !canChangeRate { return size > 1500 ? .seek(toMs: expectedMs) : .none }
        if size < 500 { return .none }
        if size <= 3000 { return .rate(drift > 0 ? 0.97 : 1.03) }
        return .seek(toMs: expectedMs)
    }

    /// Whether `next` should replace `current`: the same room only when at least as new.
    public static func shouldAdopt(_ next: WatchRoom, over current: WatchRoom?) -> Bool {
        guard let current, current.id == next.id else { return true }
        return next.revision >= current.revision
    }
}

/// Reads a Server-Sent Events stream line by line: feed it lines, get whole events back.
public struct SSEParser: Sendable {
    public struct Event: Sendable, Equatable {
        public let name: String
        public let data: String
        public let id: String?
    }

    private var name = ""
    private var data: [String] = []
    private var id: String?

    public init() {}

    /// One line, without its newline. An empty line ends the event.
    public mutating func feed(_ line: String) -> Event? {
        if line.isEmpty {
            defer { name = ""; data = []; id = nil }
            // A named event with no data still counts (Arc's `resync` can come bare).
            guard !data.isEmpty || !name.isEmpty else { return nil }
            return Event(name: name.isEmpty ? "message" : name, data: data.joined(separator: "\n"), id: id)
        }
        if line.hasPrefix(":") { return nil }
        let field: Substring
        var value: Substring = ""
        if let colon = line.firstIndex(of: ":") {
            field = line[..<colon]
            value = line[line.index(after: colon)...]
            if value.hasPrefix(" ") { value = value.dropFirst() }
        } else {
            field = Substring(line)
        }
        switch field {
        case "event": name = String(value)
        case "data": data.append(String(value))
        case "id": id = String(value)
        default: break
        }
        return nil
    }
}
