import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Play queues (arc-media-server docs/API.md, play-queues): Arc keeps one queue for this device
// and profile, so it's still there after the app restarts. Ported from arc-android's PlayQueues.

/// GET /capabilities: what this server offers the profile. A missing key means unsupported.
public struct Capabilities: Codable, Sendable {
    public struct Feature: Codable, Sendable {
        @Default<Defaults.False> public var supported: Bool
        @Default<Defaults.False> public var available: Bool
        @Default<Defaults.False> public var allowed: Bool
    }
    @Default<Defaults.Dictionary<Feature>> public var features: [String: Feature]

    /// Supported, available and allowed.
    public func usable(_ key: String) -> Bool {
        guard let f = features[key] else { return false }
        return f.supported && f.available && f.allowed
    }
}

public struct PlayQueueEntry: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public var itemId: String?
    @Default<Defaults.False> public var available: Bool
    /// None when the profile can't see the title any more.
    public var item: Item?

    /// It can be played now.
    public var playable: Bool { available && item != nil }
}

public struct PlayQueue: Codable, Sendable, Hashable {
    public let id: String
    public let revision: Int64
    @Default<Defaults.Empty> public var currentEntryId: String
    @Default<Defaults.False> public var shuffled: Bool
    @Default<Defaults.List<PlayQueueEntry>> public var entries: [PlayQueueEntry]

    public var currentIndex: Int? { entries.firstIndex { $0.id == currentEntryId } }

    /// The next entry that can be played after the current one.
    public func nextPlayable() -> PlayQueueEntry? {
        guard let at = currentIndex else { return nil }
        return entries[(at + 1)...].first(where: \.playable)
    }

    /// The current entry and what follows, playable ones only (Home's Queue row).
    public func upcoming() -> [PlayQueueEntry] {
        guard let at = currentIndex else { return [] }
        return entries[at...].filter(\.playable)
    }
}

extension ArcAPI {
    public func capabilities() async throws -> Capabilities { try await get("capabilities") }

    /// Starts this device's queue with `itemIds` (a show adds its episodes), or a playlist's
    /// titles, replacing `replace`.
    public func createPlayQueue(_ itemIds: [String], replace: PlayQueue? = nil, playlistId: String? = nil) async throws -> PlayQueue {
        var body: [String: JSONValue] = [:]
        if let playlistId { body["playlist_id"] = .string(playlistId) } else { body["item_ids"] = .array(itemIds.map(JSONValue.string)) }
        if let replace {
            body["replace_id"] = .string(replace.id)
            body["revision"] = .number(Double(replace.revision))
        }
        return try await sendJSON("POST", "play-queues", body, route: "play-queues")
    }

    /// This device and profile's queue; nil when there's none or it expired.
    public func currentPlayQueue() async throws -> PlayQueue? {
        let route = "play-queues/{id}"
        let (status, data) = try await raw("GET", "play-queues/current", route: route)
        if status == 404 { return nil }
        guard (200...299).contains(status) else { throw failure(status, data, route) }
        return try decode(PlayQueue.self, data, route)
    }

    /// One edit (append, next, remove, reorder, select, advance, shuffle…) with its fields. Arc
    /// refuses it (409) when `queue` isn't its latest revision.
    public func editPlayQueue(_ queue: PlayQueue, _ operation: String, _ fields: [String: JSONValue] = [:]) async throws -> PlayQueue {
        var body = fields
        body["revision"] = .number(Double(queue.revision))
        body["operation"] = .string(operation)
        return try await sendJSON("PATCH", "play-queues/\(enc(queue.id))", body, route: "play-queues/{id}")
    }

    public func deletePlayQueue(_ queue: PlayQueue) async throws {
        let route = "play-queues/{id}"
        let (status, data) = try await raw("DELETE", "play-queues/\(enc(queue.id))?revision=\(queue.revision)", route: route)
        guard (200...299).contains(status) || status == 404 else { throw failure(status, data, route) }
    }
}

/// This device's play queue. Playing a title starts a new one; Play Next and Add to Queue add to
/// it; the player moves it along. Calls run one at a time with the latest revision. When Arc refuses
/// an edit because the queue changed elsewhere, it's read again and the edit tried once more.
/// A server without queues is left alone: every call then does nothing (nil).
public actor PlayQueues {
    public private(set) var queue: PlayQueue?
    private var supported: Bool?
    private var last: Task<PlayQueue?, Never>?
    private let log: ArcLog
    /// Told whenever the queue changes (for Home's Queue row).
    private let changed: @Sendable (PlayQueue?) -> Void

    public init(log: ArcLog = ArcLog.shared, changed: @escaping @Sendable (PlayQueue?) -> Void = { _ in }) {
        self.log = log
        self.changed = changed
    }

    /// Whether this server keeps queues for the profile (asked once; again after a failure).
    public func supported(_ api: ArcAPI) async -> Bool {
        if let supported { return supported }
        do {
            let usable = try await api.capabilities().usable("play_queues")
            supported = usable
            return usable
        } catch {
            log.debug("capabilities unavailable: \(type(of: error))")
            return false
        }
    }

    /// Another profile: its queue is its own.
    public func reset() {
        supported = nil
        set(nil)
    }

    /// Reads the queue Arc has for this device (none: nil).
    @discardableResult
    public func refresh(_ api: ArcAPI) async -> PlayQueue? {
        await serial(api, "reading the queue") { api, _ in try await api.currentPlayQueue() }
    }

    /// A new queue of these titles, replacing the last one.
    @discardableResult
    public func start(_ api: ArcAPI, _ itemIds: [String]) async -> PlayQueue? {
        await serial(api, "starting a queue") { api, known in
            do {
                let q = try await api.createPlayQueue(itemIds, replace: known)
                return q
            } catch let error as APIError where error.status == 409 {
                // The queue this app knew changed or expired, or there's one it hasn't read yet.
                return try await api.createPlayQueue(itemIds, replace: try await api.currentPlayQueue())
            }
        }
    }

    /// Shuffle: a new queue of these titles in a random order, mixed again after the first (a
    /// show's episodes go in in order). Answers with the entry to play first.
    public func startShuffled(_ api: ArcAPI, _ itemIds: [String]) async -> PlayQueueEntry? {
        guard var q = await start(api, itemIds.shuffled()) else { return nil }
        if let mixed = await serial(api, "shuffling the queue", { api, known in
            guard let known else { return nil }
            return try await Self.edit(api, known, "shuffle", log: self.log)
        }) { q = mixed }
        return q.entries.first { $0.id == q.currentEntryId && $0.playable }
    }

    /// Play Next (`next`) or Add to Queue; with no queue yet, these titles start one.
    @discardableResult
    public func add(_ api: ArcAPI, _ itemIds: [String], next: Bool) async -> PlayQueue? {
        await serial(api, "adding to the queue") { api, known in
            var current = known
            if current == nil { current = try await api.currentPlayQueue() }
            guard let current, !current.currentEntryId.isEmpty else {
                return try await api.createPlayQueue(itemIds, replace: current)
            }
            return try await Self.edit(api, current, next ? "next" : "append", ["item_ids": .array(itemIds.map(JSONValue.string))], log: self.log)
        }
    }

    /// Points the queue at `entryId`: Advance when it's simply the next one, else Select.
    @discardableResult
    public func moveTo(_ api: ArcAPI, _ entryId: String) async -> PlayQueue? {
        await serial(api, "moving the queue on") { api, known in
            var found = known
            if found == nil { found = try await api.currentPlayQueue() }
            guard let q = found else { return nil }
            if q.currentEntryId == entryId { return q }
            if let at = q.currentIndex, at + 1 < q.entries.count, q.entries[at + 1].id == entryId {
                return try await Self.edit(api, q, "advance", log: self.log)
            }
            return try await Self.edit(api, q, "select", ["entry_id": .string(entryId)], log: self.log)
        }
    }

    /// Adds `itemId` at the end and moves the queue to it (Auto-Play's next episode, so the queue
    /// stays a true record).
    public func carryOn(_ api: ArcAPI, with itemId: String) async {
        guard let q = await add(api, [itemId], next: false),
              let entry = q.entries.last(where: { $0.itemId == itemId }) else { return }
        await moveTo(api, entry.id)
    }

    /// The queue played to its end: Arc forgets it.
    public func end(_ api: ArcAPI) async {
        _ = await serial(api, "ending the queue") { api, known in
            if let known { try await api.deletePlayQueue(known) }
            return nil
        }
    }

    /// Runs `block` after the calls before it, with the queue as last known, and keeps its answer;
    /// on failure the queue stays as it was (nil is returned).
    private func serial(_ api: ArcAPI, _ what: String,
                        _ block: @escaping @Sendable (ArcAPI, PlayQueue?) async throws -> PlayQueue?) async -> PlayQueue? {
        guard await supported(api) else { return nil }
        let previous = last
        let task = Task { () -> PlayQueue? in
            _ = await previous?.value
            do {
                let q = try await block(api, self.queue)
                self.set(q)
                return q
            } catch {
                self.log.warn("\(what) failed: \(type(of: error))")
                return nil
            }
        }
        last = task
        return await task.value
    }

    private func set(_ q: PlayQueue?) {
        queue = q
        changed(q)
    }

    private static func edit(_ api: ArcAPI, _ q: PlayQueue, _ operation: String, _ fields: [String: JSONValue] = [:], log: ArcLog) async throws -> PlayQueue? {
        do {
            return try await api.editPlayQueue(q, operation, fields)
        } catch let error as APIError where error.status == 409 {
            log.info("queue changed elsewhere; reloaded before \(operation)")
            guard let fresh = try await api.currentPlayQueue() else { return nil }
            return try await api.editPlayQueue(fresh, operation, fields)
        }
    }
}
