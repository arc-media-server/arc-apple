import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// What `GET /api/v1/discover` answers: only on the home network, and without signing in.
public struct DiscoverAnswer: Decodable, Sendable {
    /// Always "arc", so other servers on the port aren't mistaken for Arc.
    @Default<Defaults.Empty> public var product: String
    @Default<Defaults.Empty> public var id: String
    @Default<Defaults.Empty> public var name: String
    @Default<Defaults.Empty> public var version: String
    @Default<Defaults.Zero> public var apiVersion: Int
}

/// An Arc found on the home network, with the address to connect to.
public struct FoundServer: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let version: String
    public let address: URL
}

/// Finds Arc on the home network without typing its address (arc-media-server `GET /discover`),
/// as the Android app does: TV apps can't listen for broadcasts, so the Apple TV tries the
/// addresses on its own network on Arc's port, and lists the servers that answer as Arc.
public enum Discovery {
    public static let port = ServerAddress.defaultPort

    /// The addresses to try for this device's IPv4 `address` with `prefix` bits of network: the
    /// network's hosts, never more than the device's own /24 (a bigger network would be thousands
    /// of tries), and never the device itself, the network's address or its broadcast address.
    public static func candidates(address: [UInt8], prefix: Int) -> [String] {
        guard address.count == 4, (1...32).contains(prefix) else { return [] }
        let bits = max(prefix, 24)
        guard bits < 31 else { return [] }
        let ip = address.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        let mask = UInt32.max << UInt32(32 - bits)
        let network = ip & mask, broadcast = network | ~mask
        return ((network + 1)..<broadcast).filter { $0 != ip }.map { n in
            "\(n >> 24 & 0xff).\(n >> 16 & 0xff).\(n >> 8 & 0xff).\(n & 0xff)"
        }
    }

    /// A private (home network) IPv4 address: 10/8, 172.16/12 or 192.168/16.
    public static func isPrivate(_ address: [UInt8]) -> Bool {
        guard address.count == 4 else { return false }
        let a = address[0], b = address[1]
        return a == 10 || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168)
    }

    /// A session with short timeouts: most addresses on a network have nothing listening.
    public static func quickSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1.2
        config.timeoutIntervalForResource = 2
        return URLSession(configuration: config)
    }

    /// Asks each of `hosts` on `port`, `parallel` at a time, and calls `onFound` for each Arc as it
    /// answers (each server once, by its id). Returns them all, by name.
    public static func scan(hosts: [String], session: URLSession, port: Int = port, parallel: Int = 48,
                            onFound: @escaping @Sendable (FoundServer) async -> Void = { _ in }) async -> [FoundServer] {
        var seen: [String: FoundServer] = [:]
        await withTaskGroup(of: FoundServer?.self) { group in
            var index = 0
            while index < hosts.count && index < max(1, parallel) {
                let host = hosts[index]
                group.addTask { await ask(host, port: port, session: session) }
                index += 1
            }
            while let result = await group.next() {
                if let found = result, seen[found.id] == nil {
                    seen[found.id] = found
                    await onFound(found)
                }
                if Task.isCancelled { group.cancelAll(); break }
                if index < hosts.count {
                    let host = hosts[index]
                    group.addTask { await ask(host, port: port, session: session) }
                    index += 1
                }
            }
        }
        return seen.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func ask(_ host: String, port: Int, session: URLSession) async -> FoundServer? {
        guard let address = URL(string: "http://\(host):\(port)"),
              let url = URL(string: "/api/v1/discover", relativeTo: address) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let answer = try ArcJSON.decoder.decode(DiscoverAnswer.self, from: data)
            guard answer.product == "arc", answer.apiVersion >= 1 else { return nil }
            return FoundServer(id: answer.id.isEmpty ? host : answer.id, name: answer.name.isEmpty ? host : answer.name,
                               version: answer.version, address: address)
        } catch {
            // Nothing there, not Arc, or too slow: most addresses on a network are like this.
            return nil
        }
    }
}
