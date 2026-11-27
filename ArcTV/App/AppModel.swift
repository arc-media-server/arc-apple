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

/// The API client and change handler live updates read from their own thread.
final class LiveRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var current: ArcAPI?
    var api: ArcAPI? {
        get { lock.lock(); defer { lock.unlock() }; return current }
        set { lock.lock(); current = newValue; lock.unlock() }
    }
    var changed: @MainActor (Set<String>) -> Void = { _ in }
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
    /// The profile's Hide Spoilers, for every screen (from its prefs, kept up to date by Settings).
    var hideSpoilers = false
    var showMissingEpisodes = false

    /// Arc's live updates (GET /api/v1/events) while a profile's pages are on screen: each count
    /// goes up when Arc says something those pages show changed, and they reload in place.
    private(set) var liveHome = 0
    private(set) var liveTitle = 0
    private(set) var liveTogether = 0
    @ObservationIgnored private let relay: LiveRelay
    @ObservationIgnored let live: LiveUpdates

    init() {
        let relay = LiveRelay()
        self.relay = relay
        live = LiveUpdates(api: { relay.api }) { topics in
            Task { @MainActor in relay.changed(topics) }
        }
        relay.changed = { [weak self] topics in self?.liveChanged(topics) }
    }

    private let token = TokenBox()
    private let log = ArcLog.shared
    private static let serverKey = "server"
    private static let serverNameKey = "server_name"
    private static let automaticProfileKey = "automatic_profile_id"
    private(set) var automaticProfileID = UserDefaults.standard.string(forKey: AppModel.automaticProfileKey)

    func setAutomaticSignIn(_ enabled: Bool) {
        guard let profile, !profile.hasPin else { return }
        saveAutomaticProfile(enabled ? profile.id : nil)
    }

    private func saveAutomaticProfile(_ id: String?) {
        automaticProfileID = id
        UserDefaults.standard.set(id, forKey: Self.automaticProfileKey)
    }

    func refreshProfile() async {
        guard let api, let id = profile?.id,
              let current = try? await api.authStatus().profile, current.id == id,
              profile?.id == id, self.api === api else { return }
        profile = current
    }

    private func liveChanged(_ topics: Set<String>) {
        log.debug("live updates: \(topics.sorted().joined(separator: ", "))")
        if LiveTopics.touches(topics, LiveTopics.home) { liveHome += 1 }
        if LiveTopics.touches(topics, LiveTopics.title) { liveTitle += 1 }
        if LiveTopics.touches(topics, LiveTopics.together) { liveTogether += 1 }
        if LiveTopics.touches(topics, LiveTopics.prefs), let api {
            let profileId = profile?.id
            Task {
                guard let prefs = try? await api.prefs(), self.api === api, profile?.id == profileId else { return }
                hideSpoilers = prefs.hideSpoilers
                showMissingEpisodes = prefs.showMissingEpisodes
            }
        }
    }

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
        let client = makeAPI(url)
        api = client
        token.set(Keychain.read())
        // The Top Shelf reads both from the app group (installs from before it, too).
        Shared.setServer(url)
        Keychain.share()
        guard token.get() != nil else {
            saveAutomaticProfile(nil)
            stage = .signIn
            return
        }
        // Backgrounding leaves this model and its stage in place.
        if let automaticProfileID {
            do {
                let status = try await client.authStatus()
                if !status.signedIn {
                    tokenRefused()
                    return
                }
                if let selected = LaunchProfile.directProfile(status: status, automaticId: automaticProfileID, fresh: true) {
                    let chosen = if selected.id == status.profile?.id {
                        selected
                    } else {
                        try await client.chooseProfile(id: selected.id, pin: nil)
                    }
                    log.info("signing in automatically as the saved profile")
                    chose(chosen)
                    return
                }
            } catch is CancellationError {
                return
            } catch let error as APIError {
                log.warn("automatic profile sign-in failed (HTTP \(error.status))")
            } catch {
                log.warn("automatic profile sign-in failed")
            }
        }
        log.info("starting at Who's watching")
        stage = .profiles
    }

    /// Checks the address is an Arc server and keeps it. Throws when it can't be reached or isn't Arc.
    func connect(to url: URL) async throws -> Health {
        let candidate = makeAPI(url)
        let health = try await candidate.health()
        guard health.apiVersion >= 1 else { throw NotArc() }
        if serverAddress != ServerAddress.display(url) {
            forgetServerName()
            Keychain.delete()
            saveAutomaticProfile(nil)
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
        showMissingEpisodes = false
        stage = .home
        // This profile's own stream, from the start (MainView opens it while on screen).
        relay.api = api
        live.reset()
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
        saveAutomaticProfile(nil)
        token.set(nil)
        profile = nil
        stage = .signIn
    }

    func signOut() async {
        await api?.signOut()
        Keychain.delete()
        saveAutomaticProfile(nil)
        token.set(nil)
        profile = nil
        stage = .signIn
    }

    func changeServer() {
        Keychain.delete()
        saveAutomaticProfile(nil)
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
