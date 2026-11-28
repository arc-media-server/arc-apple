import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Only a fixed vocabulary is persisted or uploaded. There is no raw message field.
public final class DeviceLogs: @unchecked Sendable {
    public enum Level: String, Codable, Sendable { case debug, info, warn, error }
    public enum Event: String, Codable, Sendable {
        case launched = "app_started"
        case profilePicker = "profile_picker"
        case automaticSignIn = "automatic_sign_in"
        case signInFailed = "sign_in_failed"
        case requestFailed = "request_failed"
        case requestTimeout = "request_timeout"
        case playbackStarted = "playback_started"
        case playbackFailed = "playback_failed"
        case detailedEnabled = "detailed_logging_enabled"
        case detailedExpired = "detailed_logging_expired"
    }
    public struct Entry: Codable, Sendable {
        public let timeMs: Int64
        public let level: Level
        public let event: Event

        enum CodingKeys: String, CodingKey {
            case timeMs = "time_ms"
            case level, event
        }
    }
    private struct Saved: Codable {
        var entries: [Entry] = []
        var detailUntil: Date?
    }

    public static let shared = DeviceLogs(file: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("arc-device-logs.json"))
    private let file: URL?
    private let lock = NSLock()
    private var state = Saved()
    private var lastWrite = Date.distantPast

    init(file: URL?) {
        self.file = file
        if let file, let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size <= 256 * 1024,
           let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            state = saved
            state.entries = Array(saved.entries.suffix(3000))
        }
    }

    public var detailed: Bool {
        lock.withLock { expire(); return state.detailUntil != nil }
    }

    public func setDetailed(_ enabled: Bool) {
        lock.withLock {
            state.detailUntil = enabled ? Date().addingTimeInterval(7200) : nil
            if enabled { append(.info, .detailedEnabled) }
            write()
        }
    }

    public func record(_ level: Level, _ event: Event) {
        lock.withLock {
            expire()
            guard level != .debug || state.detailUntil != nil else { return }
            append(level, event)
            if Date().timeIntervalSince(lastWrite) >= 5 { write() }
        }
    }

    public func snapshot() -> [Entry] {
        lock.withLock { expire(); return state.entries }
    }

    public func flush() { lock.withLock { write() } }

    public func clear() {
        lock.withLock {
            state = Saved()
            lastWrite = .distantPast
            if let file { try? FileManager.default.removeItem(at: file) }
        }
    }

    private func expire() {
        if let until = state.detailUntil, until <= Date() {
            state.detailUntil = nil
            append(.info, .detailedExpired)
            write()
        }
    }

    private func append(_ level: Level, _ event: Event) {
        if state.entries.count >= 3000 { state.entries.removeFirst() }
        state.entries.append(Entry(timeMs: Int64(Date().timeIntervalSince1970 * 1000), level: level, event: event))
    }

    private func write() {
        guard let file, let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        lastWrite = Date()
    }
}

extension ArcAPI {
    public func sendDeviceLogs(_ entries: [DeviceLogs.Entry]) async throws {
        struct Upload: Encodable {
            let platform = "apple"
            let entries: [DeviceLogs.Entry]
        }
        let route = "client-logs"
        let body = try JSONEncoder().encode(Upload(entries: entries))
        let (status, data) = try await raw("POST", route, body: body, route: route)
        guard status == 204 else { throw failure(status, data, route) }
    }
}

// Never follow a redirect carrying a diagnostics POST to another destination.
final class DeviceLogRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    static let shared = DeviceLogRedirectPolicy()

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
