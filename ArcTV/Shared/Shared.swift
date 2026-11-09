import Foundation

/// What the app and its Top Shelf extension share through their app group: the server's address
/// (the token is in the Keychain), the Top Shelf's pictures, and the links the Top Shelf opens.
enum Shared {
    static let group = "group.org.arcmediaserver.apple"
    private static let serverKey = "server"

    private static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }

    static func server() -> URL? {
        defaults.string(forKey: serverKey).flatMap(URL.init(string:))
    }

    static func setServer(_ url: URL?) {
        if let url { defaults.set(url.absoluteString, forKey: serverKey) } else { defaults.removeObject(forKey: serverKey) }
    }

    /// Where the Top Shelf keeps its pictures: in the group's container, which tvOS can read
    /// (it can't send Arc's sign-in header to fetch them itself). Nil without the app group.
    static func shelfFolder() -> URL? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        let folder = container.appendingPathComponent("Library/Caches/TopShelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// The links the Top Shelf opens the app with: arcmediaserver://open/<id> (Select: the
    /// title's page) and arcmediaserver://play/<id> (Play).
    static let scheme = "arcmediaserver"

    enum Link: Equatable {
        case open(String)
        case play(String)
    }

    static func url(_ link: Link) -> URL? {
        var parts = URLComponents()
        parts.scheme = scheme
        switch link {
        case .open(let id): parts.host = "open"; parts.path = "/" + id
        case .play(let id): parts.host = "play"; parts.path = "/" + id
        }
        return parts.url
    }

    static func link(_ url: URL) -> Link? {
        guard url.scheme == scheme, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let id = String(parts.path.dropFirst())
        guard !id.isEmpty else { return nil }
        switch parts.host {
        case "open": return .open(id)
        case "play": return .play(id)
        default: return nil
        }
    }
}
