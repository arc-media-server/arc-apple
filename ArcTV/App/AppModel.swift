import ArcKit
import Foundation
import Observation
import UIKit

/// The token the API client reads on every call, swapped when signing in or out.
final class TokenBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    func get() -> String? { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ token: String?) { lock.lock(); value = token; lock.unlock() }
}

/// What the app knows about its server and who's watching. The server's address is kept in
/// UserDefaults; the device token in the Keychain.
@MainActor
@Observable
final class AppModel {
    enum Stage { case launching, server, signIn, profiles, home }

    private(set) var stage: Stage = .launching
    private(set) var api: ArcAPI?
    private(set) var profile: Profile?
    /// The server's name (Arc's Settings → Access & devices), learnt once a profile is chosen.
    private(set) var serverName: String?
    /// Whether the server sees this device on its local network (the title page's Connection
    /// line), from the last sign-in status; nil until known.
    private(set) var onLocalNetwork: Bool?
    /// A Top Shelf link waiting for Home (after the profile is chosen, on a cold start).
    var pendingLink: Shared.Link?

    private let token = TokenBox()
    private let log = ArcLog.shared
    private static let serverKey = "server"
    private static let serverNameKey = "server_name"

    var serverAddress: String? { api.map { ServerAddress.display($0.baseURL) } }

    /// The device's own name ("Living Room"), shown in Arc's list of signed-in devices.
    var deviceName: String { UIDevice.current.name }

    func launch() async {
        guard stage == .launching else { return }
        serverName = UserDefaults.standard.string(forKey: Self.serverNameKey)
        guard let saved = UserDefaults.standard.string(forKey: Self.serverKey), let url = URL(string: saved) else {
            stage = .server
            return
        }
        api = makeAPI(url)
        token.set(Keychain.read())
        // The Top Shelf reads both from the app group (installs from before it, too).
        Shared.setServer(url)
        Keychain.share()
        stage = token.get() == nil ? .signIn : .profiles
    }

    /// Checks the address is an Arc server and keeps it. Throws when it can't be reached or isn't Arc.
    func connect(to url: URL) async throws -> Health {
        let candidate = makeAPI(url)
        let health = try await candidate.health()
        guard health.apiVersion >= 1 else { throw NotArc() }
        if serverAddress != ServerAddress.display(url) {
            forgetServerName()
            Keychain.delete()
            token.set(nil)
        }
        api = candidate
        UserDefaults.standard.set(url.absoluteString, forKey: Self.serverKey)
        Shared.setServer(url)
        log.info("connected to Arc \(health.version), API v\(health.apiVersion)")
        stage = token.get() == nil ? .signIn : .profiles
        return health
    }

    func signedIn(token newToken: String) {
        Keychain.save(newToken)
        token.set(newToken)
        stage = .profiles
    }

    func chose(_ profile: Profile) {
        self.profile = profile
        stage = .home
        Task { await learnServerName() }
    }

    /// Back to the profile picker (Switch Profile).
    func switchProfile() {
        profile = nil
        stage = .profiles
    }

    /// A refused token (401): it was signed out from Arc, so ask for a new code.
    func tokenRefused() {
        log.info("the server refused this device's sign-in; asking for a new code")
        Keychain.delete()
        token.set(nil)
        profile = nil
        stage = .signIn
    }

    func signOut() async {
        await api?.signOut()
        Keychain.delete()
        token.set(nil)
        profile = nil
        stage = .signIn
    }

    func changeServer() {
        Keychain.delete()
        token.set(nil)
        profile = nil
        api = nil
        forgetServerName()
        UserDefaults.standard.removeObject(forKey: Self.serverKey)
        Shared.setServer(nil)
        stage = .server
    }

    private func learnServerName() async {
        if let local = try? await api?.authStatus().local { onLocalNetwork = local }
        guard let name = try? await api?.identity().name, !name.isEmpty else { return }
        serverName = name
        UserDefaults.standard.set(name, forKey: Self.serverNameKey)
    }

    private func forgetServerName() {
        serverName = nil
        UserDefaults.standard.removeObject(forKey: Self.serverNameKey)
    }

    private func makeAPI(_ url: URL) -> ArcAPI {
        let box = token
        return ArcAPI(baseURL: url, session: Self.session) { box.get() }
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    struct NotArc: Error {}
}
