import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A failure Arc answered with: its status, its plain-words message and what it needs next, if anything.
public struct APIError: Error, LocalizedError, Sendable {
    public let status: Int
    public let message: String
    public let needs: String?

    public var errorDescription: String? { message }
}

/// Arc answered with something this app couldn't read.
public struct UnexpectedAnswer: Error, LocalizedError, Sendable {
    public init() {}
    public var errorDescription: String? { "unexpected answer from the server" }
}

/// The answer to asking whether a TV sign-in code has been approved.
public enum LinkPoll: Sendable, Equatable {
    case waiting, expired, approved(token: String)
}

public enum ArcJSON {
    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.outputFormatting = .sortedKeys
        return e
    }()
}

/// Arc's stable API (/api/v1), signed in with a device token sent as a Bearer header.
/// Logs (through `log`) name routes only: never ids, query strings, URLs or tokens.
public final class ArcAPI: Sendable {
    public let baseURL: URL
    private let session: URLSession
    private let token: @Sendable () -> String?
    private let log: ArcLog

    public init(baseURL: URL, session: URLSession = .shared, log: ArcLog = .shared, token: @escaping @Sendable () -> String?) {
        self.baseURL = baseURL
        self.session = session
        self.token = token
        self.log = log
    }

    public func health() async throws -> Health { try await get("health") }

    public func startLink(device: String) async throws -> LinkStart {
        try await send("POST", "auth/link", body: ["device": device])
    }

    public func pollLink(_ poll: String) async throws -> LinkPoll {
        let route = "auth/link/{poll}"
        let (status, data) = try await raw("GET", "auth/link/\(enc(poll))", route: route)
        switch status {
        case 202: return .waiting
        case 404: return .expired
        case 200: return .approved(token: try decode(TokenAnswer.self, data, route).token)
        default: throw failure(status, data, route)
        }
    }

    public func authStatus() async throws -> AuthStatus { try await get("auth/status") }

    public func chooseProfile(id: String, pin: String?) async throws -> Profile {
        var body = ["id": id]
        if let pin, !pin.isEmpty { body["pin"] = pin }
        return try await send("POST", "auth/profile", body: body)
    }

    public func signOut() async {
        _ = try? await raw("POST", "auth/logout", body: Data("{}".utf8), route: "auth/logout")
    }

    /// This server's name; needs a chosen profile.
    public func identity() async throws -> Identity { try await get("identity") }

    public func libraries() async throws -> [Library] { try await get("libraries") }

    public func prefs() async throws -> Prefs { try await get("me/prefs") }

    public func continueWatching(withUpNext: Bool) async throws -> [Item] {
        try await get(withUpNext ? "home/continue?with_up_next=1" : "home/continue", route: "home/continue")
    }

    public func nextUp() async throws -> [Item] { try await get("home/next-up") }

    public func watchlist() async throws -> [Item] { try await get("watchlist") }

    /// Browse a library: `params` are /items' query parameters (library_id, kind, sort, limit...).
    public func items(_ params: [String: String]) async throws -> ItemPage {
        let query = params.keys.sorted().map { "\(enc($0))=\(enc(params[$0]!))" }.joined(separator: "&")
        return try await get("items?\(query)", route: "items")
    }

    public func recentShows(libraryId: Int64) async throws -> [RecentCard] {
        try await get("libraries/\(libraryId)/recent-shows", route: "libraries/{id}/recent-shows")
    }

    public func item(_ id: String) async throws -> Item { try await get("items/\(enc(id))", route: "items/{id}") }
    /// The four colours of a title's backdrop, worked out and kept by the server.
    public func palette(_ id: String) async throws -> ArtworkPalette {
        try await get("items/\(enc(id))/artwork/palette", route: "items/{id}/artwork/palette")
    }

    /// A show's seasons in the profile's order. `missing` adds the episodes the provider knows
    /// about that have no file (`available` false), as the web's Show Missing.
    public func seasons(seriesId: String, missing: Bool = false) async throws -> SeasonsResponse {
        try await get("series/\(enc(seriesId))/seasons" + (missing ? "?missing=1" : ""), route: "series/{id}/seasons")
    }

    public func collection(_ id: String) async throws -> CollectionPage {
        try await get("collections/\(enc(id))", route: "collections/{id}")
    }

    public func playlist(_ id: String) async throws -> PlaylistPage {
        try await get("playlists/\(enc(id))", route: "playlists/{id}")
    }

    public func startPlayback(itemId: String, request: PlaybackRequest) async throws -> PlaybackPlan {
        let route = "items/{id}/playback"
        let (status, data) = try await raw("POST", "items/\(enc(itemId))/playback", body: try ArcJSON.encoder.encode(request), route: route)
        guard (200...299).contains(status) else { throw failure(status, data, route) }
        return try decode(PlaybackPlan.self, data, route)
    }

    /// A stream address Arc gave, as a link with its own token in it (POST /cast). Apple's player
    /// fetches a converted stream's playlist and segments itself, without the app's header.
    public func castLink(for streamPath: String) async throws -> URL {
        let answer: CastAnswer = try await send("POST", "cast", body: ["url": streamPath])
        guard let url = URL(string: answer.url) else { throw UnexpectedAnswer() }
        return url
    }

    public func reportProgress(itemId: String, _ report: ProgressReport) async throws {
        let route = "items/{id}/progress"
        let (status, data) = try await raw("PUT", "items/\(enc(itemId))/progress", body: try ArcJSON.encoder.encode(report), route: route)
        guard (200...299).contains(status) else { throw failure(status, data, route) }
    }

    public func pingTranscode(_ sessionId: String) async throws {
        let route = "transcode/{sid}/ping"
        let (status, data) = try await raw("POST", "transcode/\(enc(sessionId))/ping", body: Data("{}".utf8), route: route)
        guard (200...299).contains(status) else { throw failure(status, data, route) }
    }

    public func stopTranscode(_ sessionId: String) async {
        _ = try? await raw("DELETE", "transcode/\(enc(sessionId))", route: "transcode/{sid}")
    }

    /// An address Arc gave (artwork, a stream) as a full URL. Arc answers with its unversioned
    /// /api/ paths; the same endpoints live under /api/v1/, which is what apps use.
    public func absolute(_ path: String) -> URL? {
        if path.hasPrefix("http://") || path.hasPrefix("https://") { return URL(string: path) }
        var versioned = path
        if path.hasPrefix("/api/") && !path.hasPrefix("/api/v1/") { versioned = "/api/v1/" + path.dropFirst("/api/".count) }
        return URL(string: base + versioned)
    }

    /// The headers artwork and streams fetched by the app itself need.
    public var authorization: [String: String] {
        token().map { ["Authorization": "Bearer \($0)"] } ?? [:]
    }

    // MARK: - plumbing

    private var base: String {
        var s = baseURL.absoluteString
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    func get<T: Decodable>(_ path: String, route: String? = nil) async throws -> T {
        let route = route ?? path
        let (status, data) = try await raw("GET", path, route: route)
        guard (200...299).contains(status) else { throw failure(status, data, route) }
        return try decode(T.self, data, route)
    }

    func send<T: Decodable>(_ method: String, _ path: String, body: [String: String], route: String? = nil) async throws -> T {
        let route = route ?? path
        let (status, data) = try await raw(method, path, body: try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]), route: route)
        guard (200...299).contains(status) else { throw failure(status, data, route) }
        return try decode(T.self, data, route)
    }

    func decode<T: Decodable>(_ type: T.Type, _ data: Data, _ route: String) throws -> T {
        do {
            return try ArcJSON.decoder.decode(type, from: data)
        } catch {
            log.warn("unexpected answer from \(route): \(String(describing: error).prefix(200))")
            throw UnexpectedAnswer()
        }
    }

    func failure(_ status: Int, _ data: Data, _ route: String) -> APIError {
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let message = obj?["error"] as? String ?? "the server answered \(status)"
        // Signed out, a wrong PIN or a missing profile are expected; a server error is worth a warning.
        if status >= 500 { log.warn("\(route) failed: \(status) \(message)") } else { log.debug("\(route) answered \(status)") }
        return APIError(status: status, message: message, needs: obj?["needs"] as? String)
    }

    /// Sends a request to /api/v1/`path`; `route` names it in logs without ids or query strings.
    func raw(_ method: String, _ path: String, body: Data? = nil, route: String) async throws -> (Int, Data) {
        guard let url = URL(string: base + "/api/v1/" + path) else { throw UnexpectedAnswer() }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = token() { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        do {
            let (data, response) = try await session.data(for: request)
            return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            log.warn("\(route): can't reach the server (\(type(of: error)))")
            throw error
        }
    }

    func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: Self.unreserved) ?? s
    }

    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}
