import ArcKit
import SwiftUI

/// Settings, as an iOS app's own sheet: who's watching at the top, the profile's playback
/// preferences (the same ones as Arc's Settings on the web and the Apple TV's, so they follow the
/// profile to every app), the player, the account and server, and About.
struct MobileSettingsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var prefs: Prefs?
    @State private var problem: String?
    @State private var savingMissingEpisodes = false
    @State private var confirmSignOut = false
    @AppStorage(EngineChoice.key) private var engine = ""

    var body: some View {
        NavigationStack {
            Form {
                if let profile = app.profile {
                    Section {
                        HStack(spacing: 14) {
                            Avatar(profile: profile, size: 56)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.name).font(.headline)
                                if let name = app.serverName { Text(name).font(.subheadline).foregroundStyle(ArcColor.muted) }
                            }
                        }
                        .padding(.vertical, 4)
                        Button(L("settings.switch_profile")) {
                            dismiss()
                            app.switchProfile()
                        }
                    }
                }
                Section(L("settings.playback")) {
                    if let prefs {
                        Toggle(L("settings.auto_play"), isOn: binding(prefs.autoPlay, "auto_play") { $0.autoPlay = $1 })
                        Toggle(L("settings.auto_skip"), isOn: binding(prefs.autoSkip, "auto_skip") { $0.autoSkip = $1 })
                        Toggle(L("settings.theme_music"), isOn: binding(prefs.themeMusic, "theme_music") { $0.themeMusic = $1 })
                        Toggle(L("settings.hide_spoilers"), isOn: binding(prefs.hideSpoilers, "hide_spoilers") { $0.hideSpoilers = $1 })
                        Toggle(L("settings.show_missing_episodes"), isOn: binding(prefs.showMissingEpisodes, "show_missing_episodes") { $0.showMissingEpisodes = $1 })
                            .disabled(savingMissingEpisodes)
                        Picker(L("settings.subtitles"), selection: Binding(get: { prefs.subtitleMode }, set: { mode in save("subtitle_mode", .string(mode)) { $0.subtitleMode = mode } })) {
                            Text(L("settings.subtitles_last")).tag("")
                            Text(L("settings.subtitles_foreign")).tag("foreign")
                            Text(L("settings.subtitles_always")).tag("always")
                            Text(L("settings.subtitles_manual")).tag("manual")
                        }
                        if let problem { Text(problem).foregroundStyle(ArcColor.error) }
                    } else if let problem {
                        Text(problem).foregroundStyle(ArcColor.error)
                    } else {
                        ProgressView()
                    }
                    // Which player plays: this device's own choice, as on the Apple TV.
                    Picker(L("about.player"), selection: $engine) {
                        Text(L("player.engine_mpv")).tag("")
                        Text(L("player.engine_apple")).tag("apple")
                    }
                }
                Section(L("together.title")) {
                    NavigationLink(L("together.join_with_code")) { MobileJoinCodeScreen { dismiss() } }
                        .accessibilityIdentifier("settings.join_code")
                }
                Section(L("settings.account")) {
                    if let profile = app.profile {
                        Toggle(isOn: Binding(
                            get: { !profile.hasPin && app.automaticProfileID == profile.id },
                            set: { app.setAutomaticSignIn($0) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L("settings.automatic_sign_in"))
                                Text(profile.hasPin ? L("settings.automatic_sign_in_pin")
                                    : L("settings.automatic_sign_in_hint", profile.name))
                                    .font(.footnote)
                                    .foregroundStyle(ArcColor.muted)
                            }
                        }
                        .disabled(profile.hasPin)
                    }
                    Button(L("signin.change_server")) {
                        dismiss()
                        app.changeServer()
                    }
                    Button(L("profiles.sign_out"), role: .destructive) { confirmSignOut = true }
                }
                Section {
                    NavigationLink { MobileAboutScreen() } label: {
                        LabeledContent(L("settings.about"), value: AboutText.appVersion)
                    }
                }
            }
            .navigationTitle(L("tab.settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("mobile.done")) { dismiss() }.accessibilityIdentifier("settings.done")
                }
            }
            .confirmationDialog(L("settings.sign_out_title"), isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button(L("profiles.sign_out"), role: .destructive) {
                    dismiss()
                    Task { await app.signOut() }
                }
                Button(L("common.cancel"), role: .cancel) {}
            } message: {
                Text(L("settings.sign_out_body"))
            }
        }
        .task { await app.refreshProfile() }
        .task { await load() }
        .onChange(of: prefs?.hideSpoilers) { _, on in if let on { app.hideSpoilers = on } }
    }

    private func binding(_ value: Bool, _ key: String, _ apply: @escaping (inout Prefs, Bool) -> Void) -> Binding<Bool> {
        Binding(get: { value }, set: { new in save(key, .bool(new)) { apply(&$0, new) } })
    }

    /// Shows the change at once and sends just that preference; puts it back if Arc refuses it
    /// (as the Apple TV's Settings).
    private func save(_ key: String, _ value: JSONValue, _ apply: (inout Prefs) -> Void) {
        guard var changed = prefs, let api = app.api else { return }
        let changesMissingEpisodes = key == "show_missing_episodes"
        if changesMissingEpisodes {
            guard !savingMissingEpisodes else { return }
            savingMissingEpisodes = true
        }
        let before = prefs
        let profileId = app.profile?.id
        apply(&changed)
        prefs = changed
        problem = nil
        Task {
            defer { if changesMissingEpisodes { savingMissingEpisodes = false } }
            do {
                let saved = try await api.updatePrefs([key: value])
                guard app.api === api, app.profile?.id == profileId else { return }
                prefs = saved
                if changesMissingEpisodes { app.showMissingEpisodes = saved.showMissingEpisodes }
                ArcLogApp.info("preference changed: \(key)")
            } catch let error as APIError where error.status == 401 {
                app.tokenRefused()
            } catch {
                ArcLogApp.warn("saving the preference \(key) failed: \(type(of: error))")
                prefs = before
                problem = L("settings.not_saved")
            }
        }
    }

    private func load() async {
        let (answer, failed) = await loadPage(app, "preferences") { try await $0.prefs() }
        prefs = answer ?? prefs
        problem = failed
    }
}

enum AboutText {
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

/// About: this app's and the server's versions, where the details and pictures come from, and
/// the open source licences.
struct MobileAboutScreen: View {
    @Environment(AppModel.self) private var app
    @State private var health: Health?

    private static let parts: [(name: String, licence: String)] = [
        ("Arc for iPhone and iPad", "AGPL-3.0"),
        ("mpv", "GPL-3.0 (as built)"),
        ("FFmpeg", "GPL-3.0 (as built)"),
        ("mpv-build (edde746)", "GPL-3.0"),
        ("libass", "ISC"),
        ("libplacebo", "LGPL-2.1"),
        ("FreeType", "FreeType License"),
        ("HarfBuzz", "MIT"),
        ("FriBidi", "LGPL-2.1"),
    ]

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    ArcWordmark(stacked: true, height: 72)
                    Text(L("mobile.about_name")).font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            Section(L("about.this_app")) {
                LabeledContent(L("about.version"), value: AboutText.appVersion)
                LabeledContent(L("about.player"), value: EngineChoice.prefersApple ? L("player.engine_apple") : L("player.engine_mpv"))
            }
            Section(L("about.server")) {
                LabeledContent(L("about.server_name"), value: app.serverName ?? health?.name ?? "")
                LabeledContent(L("about.server_version"), value: health.map { $0.version.isEmpty ? "?" : $0.version } ?? "…")
                LabeledContent(L("about.api"), value: health.map { "v\($0.apiVersion)" } ?? "…")
                LabeledContent(L("about.address"), value: app.serverAddress ?? "")
                if let local = app.onLocalNetwork {
                    LabeledContent(L("details.connection"), value: L(local ? "details.connection_local" : "details.connection_remote"))
                }
            }
            Section {
                ForEach(Self.parts, id: \.name) { part in
                    LabeledContent(part.name, value: part.licence)
                }
            } header: {
                Text(L("about.licences"))
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("mobile.licences_note"))
                    // TheTVDB and TMDB ask to be credited where their details and pictures show.
                    Text(L("settings.attribution"))
                }
            }
        }
        .navigationTitle(L("settings.about"))
        .task { health = try? await app.api?.health() }
    }
}

/// Add to Playlist as a sheet: the profile's playlists that can be added to (smart playlists
/// fill themselves), each with how many titles it holds. Choosing one adds the title and says so.
/// Playlists are made on the web, as on the Apple TV.
struct MobilePlaylistSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(Browse.self) private var browse
    let item: Item
    @State private var playlists: [PlaylistSummary]?
    @State private var failed = false
    @State private var busy = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let playlists {
                        if playlists.isEmpty {
                            Text(L("playlist_add.none")).foregroundStyle(ArcColor.muted)
                        }
                        ForEach(playlists) { list in
                            Button { add(to: list) } label: {
                                HStack {
                                    Label(list.title, systemImage: "list.bullet.rectangle").foregroundStyle(ArcColor.foreground)
                                    Spacer()
                                    Text(L("playlist_add.count", list.count)).font(.footnote).foregroundStyle(ArcColor.muted)
                                }
                            }
                            .disabled(busy)
                        }
                    } else if failed {
                        Text(L("playlist_add.load_failed")).foregroundStyle(ArcColor.muted)
                        Button(L("common.retry")) { Task { await load() } }
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                } footer: {
                    Text(L(item.isSeries ? "playlist_add.body_show" : "playlist_add.body", item.title))
                }
            }
            .navigationTitle(L("playlist_add.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common.cancel")) { browse.addingToPlaylist = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task { await load() }
    }

    private func load() async {
        guard let api = app.api else { return }
        failed = false
        do {
            playlists = try await api.playlists().filter(\.editable)
        } catch let error as APIError where error.status == 401 {
            app.tokenRefused()
        } catch is CancellationError {
        } catch {
            ArcLogApp.warn("playlists failed to load for Add to Playlist: \(type(of: error))")
            failed = true
        }
    }

    private func add(to list: PlaylistSummary) {
        guard let api = app.api else { return }
        busy = true
        let item = item
        Task {
            do {
                try await api.addToPlaylist(list.id, itemIds: [item.id])
                ArcLogApp.debug("title action done: added to a playlist")
                browse.note(L("playlist_add.added", item.title, list.title))
            } catch let error as APIError where error.status == 401 {
                app.tokenRefused()
            } catch {
                ArcLogApp.warn("adding to a playlist failed: \(type(of: error))")
                browse.note(L("playlist_add.failed", item.title))
            }
            busy = false
            browse.addingToPlaylist = nil
        }
    }
}
