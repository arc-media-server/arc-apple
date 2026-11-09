import ArcKit
import Foundation
import Observation

/// What the player reports to the room every couple of seconds.
struct RoomReport {
    let positionMs: Int64
    /// playing, paused or waiting (loading).
    let state: String
    let ready: Bool
}

/// Watch Together for this Apple TV (docs/plans/watch-together.md): the rooms on Home's row, the
/// room this device is in, its live stream, heartbeats and clock, and the commands the player
/// sends. The player follows `room`: it plays the room's title from where the room is.
@MainActor
@Observable
final class WatchTogetherModel {
    /// Rooms this profile made, was invited to or is in (Home's Watch Together row).
    private(set) var rooms: [ListedRoom] = []
    /// The room this device is in, as of the latest word from Arc.
    private(set) var room: WatchRoom?
    /// The code for a room this device made, while it's valid.
    private(set) var code: String?
    /// A short note for the capsule ("Paused by Sam", "Room ready…"); cleared after a few seconds.
    private(set) var notice: String?
    /// Who to invite, while the invite panel is open: a title for a new room, or the room's own.
    var inviting: InviteTarget?
    /// The code entry, while it's open.
    var enteringCode = false
    /// The title each listed room plays, for its card's picture.
    private(set) var titles: [String: Item] = [:]

    struct InviteTarget: Identifiable, Equatable {
        let itemId: String
        let title: String
        /// Inviting more people to this room, rather than making a new one.
        var roomId: String?
        var id: String { (roomId ?? "new") + "|" + itemId }
    }

    private var api: ArcAPI?
    private var offsetMs: Double = 0
    private var tasks: [Task<Void, Never>] = []
    private var noticeTask: Task<Void, Never>?
    /// The player's report, read for each heartbeat, and which player set it.
    var reporter: (() -> RoomReport?)?
    var reporterOwner: UUID?
    /// Opens the player on a title (Browse.play), for joining and for the room changing title.
    var openPlayer: ((Item, Int64) -> Void)?
    private let log = ArcLog.shared

    var inRoom: Bool { room != nil }

    // MARK: - the rooms list

    func refreshRooms(_ api: ArcAPI) async {
        self.api = api
        do {
            let list = try await api.watchRooms()
            rooms = list
            for r in list where titles[r.item.id] == nil {
                if let item = try? await api.item(r.item.id) { titles[r.item.id] = item }
            }
        } catch is CancellationError {
        } catch let error as APIError where error.status == 404 {
            rooms = [] // an Arc without Watch Together
        } catch {
            log.debug("Watch Together rooms unavailable: \(type(of: error))")
        }
    }

    /// Makes a room for the chosen people; it waits on their Home rows (and this one's).
    func createRoom(_ api: ArcAPI, itemId: String, title: String, people: [String]) async throws {
        let made = try await api.createInvitedRoom(itemId: itemId, profileIds: people)
        code = WatchCode.format(made.inviteCode)
        codeRoom = made.room.id
        log.info("Watch Together room made for \(people.count) people")
        say(L("together.room_ready", title))
        await refreshRooms(api)
    }

    /// The room for `code` belongs to this room id (a code shows only in its own lobby).
    private var codeRoom: String?

    /// A room with a code, joined straight away (Use a code instead).
    func startWithCode(_ api: ArcAPI, item: Item) async throws {
        let made = try await api.createRoom(itemId: item.id)
        code = WatchCode.format(made.inviteCode)
        codeRoom = made.room.id
        begin(api, made.room)
    }

    func accept(_ api: ArcAPI, _ listed: ListedRoom) async throws {
        begin(api, try await api.acceptRoom(listed.id))
    }

    func join(_ api: ArcAPI, code typed: String) async throws {
        begin(api, try await api.joinRoom(code: typed))
    }

    /// Declines, or (for the host) cancels the room.
    func dismiss(_ api: ArcAPI, _ listed: ListedRoom) async {
        do { try await api.dismissRoom(listed.id) } catch { log.debug("dismissing a room failed: \(type(of: error))") }
        await refreshRooms(api)
    }

    func invite(_ api: ArcAPI, roomId: String, people: [String]) async throws {
        adopt(try await api.invitePeople(roomId, profileIds: people))
    }

    /// The code to show in the lobby: only this device's own room's.
    var lobbyCode: String? { room?.id == codeRoom ? code : nil }

    // MARK: - being in a room

    private func begin(_ api: ArcAPI, _ joined: WatchRoom) {
        stop()
        self.api = api
        room = joined
        log.info("joined a Watch Together room (\(joined.participants.count) here)")
        tasks = [
            Task { [weak self] in await self?.streamLoop() },
            Task { [weak self] in
                while !Task.isCancelled {
                    await self?.syncClock()
                    try? await Task.sleep(for: .seconds(60))
                }
            },
            Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    await self?.heartbeat()
                }
            },
        ]
        Task { await openRoomTitle() }
    }

    /// Plays the room's title from where the room is.
    private func openRoomTitle() async {
        guard let api, let room, room.available, let id = room.itemId else { return }
        do {
            let item = try await api.item(id)
            openPlayer?(item, Int64(expectedMs()))
        } catch {
            log.warn("the room's title didn't load: \(type(of: error))")
        }
    }

    /// Leaves the room (closing the player does this).
    func leave() {
        guard let room, let api else { return }
        stop()
        self.room = nil
        Task { await api.leaveRoom(room.id); await refreshRooms(api) }
        log.info("left the Watch Together room")
    }

    /// Ends the room for everyone (host).
    func end() async {
        await command("end")
    }

    private func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
    }

    private func gone(_ why: String) {
        stop()
        room = nil
        say(why)
        if let api { Task { await refreshRooms(api) } }
    }

    /// The server's clock now, as well as this device can tell.
    var serverNowMs: Double { Date().timeIntervalSince1970 * 1000 + offsetMs }

    func expectedMs() -> Double {
        guard let room else { return 0 }
        return WatchSync.expectedPosition(room, serverNowMs: serverNowMs)
    }

    func play() async { await command("play") }
    func pause() async { await command("pause") }
    func seek(toMs ms: Int64) async { await command("seek", positionMs: max(0, ms)) }
    func changeItem(_ id: String) async { await command("change_item", positionMs: 0, itemId: id) }

    /// Sends a command with the room's revision; if the room changed meanwhile, adopts it and
    /// tries once more.
    private func command(_ action: String, positionMs: Int64? = nil, itemId: String? = nil) async {
        guard let api, let current = room else { return }
        do {
            adopt(try await api.roomCommand(current.id, revision: current.revision, action: action, positionMs: positionMs, itemId: itemId))
        } catch let conflict as RoomConflict {
            adopt(conflict.room)
            guard let again = room else { return }
            do {
                adopt(try await api.roomCommand(again.id, revision: again.revision, action: action, positionMs: positionMs, itemId: itemId))
            } catch {
                log.debug("room command \(action) refused again: \(type(of: error))")
            }
        } catch let error as APIError where error.status == 404 {
            gone(L("together.lost"))
        } catch {
            log.warn("room command \(action) failed: \(type(of: error))")
        }
    }

    private func heartbeat() async {
        guard let api, let current = room, let report = reporter?() else { return }
        do {
            adopt(try await api.roomHeartbeat(current.id, generation: current.generation, positionMs: report.positionMs,
                                               state: report.state, ready: report.ready && report.state != "waiting"))
        } catch let conflict as RoomConflict {
            adopt(conflict.room) // a seek or new title: report against it next time
        } catch let error as APIError where error.status == 404 {
            gone(L("together.lost"))
        } catch {
            // Offline for a moment: the next beat tries again.
        }
    }

    private func syncClock() async {
        guard let api else { return }
        var samples: [ClockSample] = []
        for _ in 0..<3 {
            let c0 = Int64(Date().timeIntervalSince1970 * 1000)
            guard let t = try? await api.serverTime(clientSentMs: c0) else { break }
            samples.append(ClockSample(c0: c0, c3: Int64(Date().timeIntervalSince1970 * 1000), s1: t.serverReceivedMs, s2: t.serverSentMs))
        }
        if let offset = WatchSync.clockOffset(samples) { offsetMs = offset }
    }

    /// The room's live stream: the whole room on every change. Reconnects with a growing pause;
    /// a room that's gone (404) ends this membership.
    private func streamLoop() async {
        var backoff: Double = 2
        while !Task.isCancelled {
            guard let api, let id = room?.id, let request = api.roomEventsRequest(id) else { return }
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 404 { gone(L("together.lost")); return }
                guard status == 200 else { throw URLError(.badServerResponse) }
                backoff = 2
                // Lines split by hand: `bytes.lines` drops the blank lines that end each event.
                var parser = SSEParser()
                var line = Data()
                for try await byte in bytes {
                    guard byte == 10 else { line.append(byte); continue }
                    if line.last == 13 { line.removeLast() }
                    let text = String(decoding: line, as: UTF8.self)
                    line.removeAll(keepingCapacity: true)
                    if let event = parser.feed(text), event.name == "room",
                       let next = try? ArcJSON.decoder.decode(WatchRoom.self, from: Data(event.data.utf8)) {
                        adopt(next)
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                log.debug("room stream dropped: \(type(of: error))")
            }
            try? await Task.sleep(for: .seconds(backoff))
            backoff = min(backoff * 2, 30)
        }
    }

    /// Takes a room from Arc if it's at least as new as the one held, and says what changed.
    func adopt(_ next: WatchRoom) {
        // Not in a room (left already), or older than what's held: ignore it.
        guard let current = room, WatchSync.shouldAdopt(next, over: current) else { return }
        room = next
        if next.state == "ended" {
            stop()
            room = nil
            say(L("together.ended"))
            if let api { Task { await refreshRooms(api) } }
            return
        }
        // The room moved to another title (the host's Up Next): follow it.
        if next.itemId != nil, next.itemId != current.itemId {
            Task { await openRoomTitle() }
        }
        noticeFor(next, after: current)
    }

    /// "Paused by Sam" when someone else changes the shared timeline.
    private func noticeFor(_ next: WatchRoom, after before: WatchRoom) {
        guard next.revision > before.revision, let by = next.changedBy, by != next.selfId,
              let who = next.participants.first(where: { $0.id == by })?.name else { return }
        if next.generation != before.generation {
            say(L("together.moved_by", who))
        } else if next.state == "paused" && before.state != "paused" {
            say(L("together.paused_by", who))
        } else if next.state == "playing" && before.state == "paused" {
            say(L("together.played_by", who))
        }
    }

    func say(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { self?.notice = nil }
        }
    }
}
