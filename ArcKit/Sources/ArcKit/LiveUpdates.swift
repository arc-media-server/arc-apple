import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Live updates (arc-media-server docs/EVENTS-API.md): Arc sends "something changed" hints on
// /api/v1/events, naming a topic only (never the record), and the app reloads what's on screen.
// Ported from arc-android's LiveHints.kt and LiveUpdates.kt.

public enum LiveTopics {
    /// Not a topic Arc sends as such: "anything may have changed" (a resync, or a gap in the stream).
    public static let resync = "resync"
    /// Home's rows and the sidebar's libraries.
    public static let home: Set<String> = ["catalog", "library", "profile", "playback", "artwork"]
    /// A title's page: its details, seasons and watched state.
    public static let title: Set<String> = ["catalog", "profile", "playback", "artwork"]
    /// The profile's preferences (Hide Spoilers…).
    public static let prefs: Set<String> = ["profile"]
    /// Home's Watch Together rooms: a personal hint when one is made, joined, declined or ended.
    public static let together: Set<String> = ["watch_together"]

    /// Whether hints for `topics` mean a screen that follows `wanted` should reload.
    public static func touches(_ topics: Set<String>, _ wanted: Set<String>) -> Bool {
        topics.contains(resync) || !topics.isDisjoint(with: wanted)
    }

    /// The topic of an `invalidate` hint ({"topic":"catalog", …}), or nil if it can't be read.
    public static func topic(_ data: String) -> String? {
        let object = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any]
        return object?["topic"] as? String
    }
}

/// Splits a byte stream into lines ending in LF, CR LF or CR, as server-sent events allow.
public struct SSELineSplitter: Sendable {
    private var pending = [UInt8]()
    private var afterCR = false

    public init() {}

    public mutating func feed(_ bytes: Data) -> [String] {
        var lines: [String] = []
        for byte in bytes {
            if afterCR {
                afterCR = false
                if byte == 0x0A { continue }
            }
            if byte == 0x0A || byte == 0x0D {
                lines.append(String(decoding: pending, as: UTF8.self))
                pending.removeAll(keepingCapacity: true)
                afterCR = byte == 0x0D
            } else {
                pending.append(byte)
            }
        }
        return lines
    }
}

/// Collects hints and hands them on at most once every `spacingMs`, the first `firstMs` after a
/// quiet spell, as the web's HintBatcher: a library scan sends hints twice a second for minutes,
/// and reloading Home for each would never settle.
public final class HintBatcher: @unchecked Sendable {
    private let lock = NSLock()
    private let firstMs: Int
    private let spacingMs: Int
    private let flush: @Sendable (Set<String>) -> Void
    private var pending = Set<String>()
    private var timer: Task<Void, Never>?
    private var last = Date.distantPast

    public init(firstMs: Int = 1_500, spacingMs: Int = 5_000, flush: @escaping @Sendable (Set<String>) -> Void) {
        self.firstMs = firstMs
        self.spacingMs = spacingMs
        self.flush = flush
    }

    public func add(_ topic: String) {
        lock.lock(); defer { lock.unlock() }
        pending.insert(topic)
        guard timer == nil else { return }
        let sinceLast = Int(Date().timeIntervalSince(last) * 1000)
        let wait = max(firstMs, spacingMs - sinceLast)
        timer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait) * 1_000_000)
            if !Task.isCancelled { self?.run() }
        }
    }

    /// Hands on what's waiting now (after a reconnect, everything is stale at once).
    public func run() {
        lock.lock()
        timer?.cancel()
        timer = nil
        let topics = pending
        pending.removeAll()
        if !topics.isEmpty { last = Date() }
        lock.unlock()
        if !topics.isEmpty { flush(topics) }
    }

    public func stop() {
        lock.lock(); defer { lock.unlock() }
        timer?.cancel()
        timer = nil
        pending.removeAll()
    }
}

/// Keeps one /api/v1/events stream open while the app is on screen (`start` / `stop`) and hands
/// on what changed through `onChange`, gathered by HintBatcher. As the web's and Android's:
/// - A new stream (no cursor) starts with a resync: the screens have just loaded, so it's skipped.
/// - A resync on a resumed stream is real (Arc's replay window didn't reach back far enough).
/// - After a gap with no stream (a refusal or a lost connection), everything refreshes once back.
/// - The stream resumes with Last-Event-ID; Arc closes streams after 30 minutes and the app reopens.
/// - A refusal (429 when Arc's streams are all in use) is honoured with its Retry-After, else 5 s
///   doubling to a minute.
public final class LiveUpdates: @unchecked Sendable {
    private let api: @Sendable () -> ArcAPI?
    private let configuration: URLSessionConfiguration
    private let log: ArcLog
    private let batcher: HintBatcher
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var cursor: String?
    private var wanted = false

    public init(api: @escaping @Sendable () -> ArcAPI?, configuration: URLSessionConfiguration = .default,
                log: ArcLog = .shared, firstMs: Int = 1_500, spacingMs: Int = 5_000,
                onChange: @escaping @Sendable (Set<String>) -> Void) {
        self.api = api
        // Arc sends a heartbeat every 10 s, so a read that waits much longer means the line is dead.
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 3_600
        self.configuration = configuration
        self.log = log
        batcher = HintBatcher(firstMs: firstMs, spacingMs: spacingMs, flush: onChange)
    }

    /// The app came to the front (or a profile was chosen).
    public func start() {
        lock.lock(); defer { lock.unlock() }
        wanted = true
        if task == nil { task = Task { [weak self] in await self?.run() } }
    }

    /// The app went to the background: no stream. It resumes from where it was on `start`.
    public func stop() {
        lock.lock(); defer { lock.unlock() }
        wanted = false
        close()
    }

    /// A different profile (or none): its stream starts afresh, if the app is on screen.
    public func reset() {
        lock.lock(); defer { lock.unlock() }
        close()
        cursor = nil
        if wanted { task = Task { [weak self] in await self?.run() } }
    }

    private func close() {
        task?.cancel()
        task = nil
        batcher.stop()
    }

    private var savedCursor: String? {
        get { lock.lock(); defer { lock.unlock() }; return cursor }
        set { lock.lock(); cursor = newValue; lock.unlock() }
    }

    private func run() async {
        var backoff = 5_000
        var missed = false
        var failures = 0
        while !Task.isCancelled {
            guard let api = api(), let request = api.eventsRequest(cursor: savedCursor) else { return }
            var wait: Int
            do {
                let outcome = try await stream(request) {
                    // Connected: anything could have changed while there was no stream.
                    backoff = 5_000
                    if failures > 0 { self.log.debug("live updates: connected again") }
                    failures = 0
                    if missed {
                        missed = false
                        self.batcher.add(LiveTopics.resync)
                        self.batcher.run()
                    }
                }
                if outcome.ended {
                    wait = 1_000 // Arc closed it (after 30 minutes): reopen, resuming.
                } else {
                    failures += 1
                    missed = true
                    // Logged once in a row: Arc refusing is ordinary when its streams are full.
                    if failures == 1 { log.warn("live updates: Arc answered \(outcome.status); trying again later") }
                    if let retry = outcome.retryAfterMs { wait = retry } else { wait = backoff; backoff = min(backoff * 2, 60_000) }
                }
            } catch {
                if Task.isCancelled { return }
                failures += 1
                missed = true
                if failures == 1 { log.warn("live updates: the stream dropped (\(type(of: error))); trying again later") }
                else { log.debug("live updates: still can't connect (\(type(of: error)))") }
                wait = backoff
                backoff = min(backoff * 2, 60_000)
            }
            try? await Task.sleep(nanoseconds: UInt64(wait) * 1_000_000)
        }
    }

    struct Outcome { let ended: Bool; var status = 200; var retryAfterMs: Int? = nil }

    /// Reads one stream until it ends; `connected` once Arc accepts it.
    private func stream(_ request: URLRequest, connected: () -> Void) async throws -> Outcome {
        let stream = EventStream(request, configuration)
        return try await withTaskCancellationHandler {
            let response = try await stream.response()
            guard (200...299).contains(response.statusCode) else {
                stream.cancel()
                let retry = (response.value(forHTTPHeaderField: "Retry-After")).flatMap(Int.init).flatMap { (1...600).contains($0) ? $0 * 1000 : nil }
                return Outcome(ended: false, status: response.statusCode, retryAfterMs: retry)
            }
            connected()
            // No cursor: Arc starts the stream with a resync, which the screens just loaded don't need.
            var fresh = savedCursor == nil
            var parser = SSEParser()
            for try await line in stream.lines {
                guard let event = parser.feed(line) else { continue }
                if let id = event.id { savedCursor = id }
                switch event.name {
                case "invalidate":
                    fresh = false
                    if let topic = LiveTopics.topic(event.data) { batcher.add(topic) }
                case "resync":
                    if fresh { fresh = false } else { batcher.add(LiveTopics.resync) }
                default: break
                }
            }
            return Outcome(ended: true)
        } onCancel: {
            stream.cancel()
        }
    }
}

/// One open text/event-stream request, read as lines as they arrive (URLSession's delegate works
/// on every platform Arc's code is tested on, unlike its async bytes).
final class EventStream: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let lines: AsyncThrowingStream<String, Error>
    private let linesOut: AsyncThrowingStream<String, Error>.Continuation
    private let lock = NSLock()
    private var splitter = SSELineSplitter()
    private var answered: HTTPURLResponse?
    private var failed: Error?
    private var waiting: CheckedContinuation<HTTPURLResponse, Error>?
    private var session: URLSession?
    private var dataTask: URLSessionDataTask?

    init(_ request: URLRequest, _ configuration: URLSessionConfiguration) {
        (lines, linesOut) = AsyncThrowingStream.makeStream(of: String.self)
        super.init()
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        dataTask = session.dataTask(with: request)
        dataTask?.resume()
    }

    /// Arc's answer to the request (its status and headers), once it comes.
    func response() async throws -> HTTPURLResponse {
        try await withCheckedThrowingContinuation { c in
            lock.lock()
            if let answered { lock.unlock(); c.resume(returning: answered); return }
            if let failed { lock.unlock(); c.resume(throwing: failed); return }
            waiting = c
            lock.unlock()
        }
    }

    func cancel() {
        lock.lock()
        let session = self.session
        self.session = nil
        lock.unlock()
        session?.invalidateAndCancel()
        finish(CancellationError())
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let http = response as? HTTPURLResponse ?? HTTPURLResponse(url: response.url ?? URL(fileURLWithPath: "/"), statusCode: 0, httpVersion: nil, headerFields: nil)!
        lock.lock()
        answered = http
        let c = waiting
        waiting = nil
        lock.unlock()
        c?.resume(returning: http)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        let found = splitter.feed(data)
        lock.unlock()
        for line in found { linesOut.yield(line) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(error)
        session.finishTasksAndInvalidate()
    }

    private func finish(_ error: Error?) {
        lock.lock()
        if failed == nil, answered == nil { failed = error ?? URLError(.badServerResponse) }
        let c = waiting
        waiting = nil
        let stillFailed = failed
        lock.unlock()
        if let c, let stillFailed { c.resume(throwing: stillFailed) }
        if let error { linesOut.finish(throwing: error) } else { linesOut.finish() }
    }
}
