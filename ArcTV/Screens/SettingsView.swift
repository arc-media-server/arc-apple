import ArcKit
import SwiftUI

/// Settings, laid out as tvOS's own: the profile on the left where Settings shows its icon, the
/// list on the right. The profile's playback preferences (the same ones as Arc's Settings on the
/// web, so they follow the profile to every app), Watch Together, the profile and server, and
/// About (versions, the data sources and the open source licences).
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(Browse.self) private var browse
    @State private var prefs: Prefs?
    @State private var problem: String?
    @State private var savingMissingEpisodes = false
    @State private var confirmSignOut = false
    @State private var detailedLogs = DeviceLogs.shared.detailed
    @State private var sendingLogs = false
    @State private var logStatus: String?

    var body: some View {
        SettingsLayout {
            // Who's watching, where tvOS's Settings shows its icon.
            if let profile = app.profile {
                VStack(spacing: 24) {
                    Avatar(profile: profile, size: 260)
                    Text(profile.name).font(.title3.weight(.semibold))
                    if let name = app.serverName { Text(name).foregroundStyle(ArcColor.muted) }
                }
            }
        } rows: {
            List {
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
                        // Its own list, as tvOS's Settings: the choices are too long side by side.
                        .pickerStyle(.navigationLink)
                        if let problem { Text(problem).foregroundStyle(ArcColor.error) }
                    } else if let problem {
                        Text(problem).foregroundStyle(ArcColor.error)
                    } else {
                        ProgressView()
                    }
                }
                Section(L("together.title")) {
                    Button(L("together.join_with_code")) { browse.together.enteringCode = true }
                }
                Section(L("settings.account")) {
                    if let profile = app.profile {
                        Toggle(isOn: Binding(
                            get: { !profile.hasPin && app.automaticProfileID == profile.id },
                            set: { app.setAutomaticSignIn($0) }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L("settings.automatic_sign_in"))
                                Text(profile.hasPin ? L("settings.automatic_sign_in_pin")
                                    : L("settings.automatic_sign_in_hint", profile.name))
                                    .font(.callout)
                                    .foregroundStyle(ArcColor.muted)
                            }
                        }
                        .disabled(profile.hasPin)
                    }
                    Button(L("settings.switch_profile")) { app.switchProfile() }
                    Button(L("profiles.sign_out")) { confirmSignOut = true }
                    Button(L("signin.change_server")) { app.changeServer() }
                }
                Section {
                    Toggle(L("diagnostics.detailed"), isOn: Binding(get: { detailedLogs }, set: { enabled in
                        DeviceLogs.shared.setDetailed(enabled)
                        detailedLogs = enabled
                    }))
                    Button(L("diagnostics.send")) { sendLogs() }
                        .accessibilityIdentifier("send-device-logs")
                        .disabled(sendingLogs)
                    Text(logStatus ?? L("diagnostics.note")).font(.callout).foregroundStyle(ArcColor.muted)
                }
                Section {
                    NavigationLink { AboutView() } label: {
                        LabeledContent(L("settings.about"), value: AboutView.appVersion)
                    }
                }
            }
        }
        .task { await app.refreshProfile() }
        .task {
            while !Task.isCancelled {
                detailedLogs = DeviceLogs.shared.detailed
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
        .task { await load() }
        // Every screen keeps unwatched episodes' stills and descriptions back at once.
        .onChange(of: prefs?.hideSpoilers) { _, on in if let on { app.hideSpoilers = on } }
        .confirmationDialog(L("settings.sign_out_title"), isPresented: $confirmSignOut) {
            Button(L("profiles.sign_out"), role: .destructive) { Task { await app.signOut() } }
            Button(L("common.cancel"), role: .cancel) {}
        } message: {
            Text(L("settings.sign_out_body"))
        }
    }

    private func sendLogs() {
        guard let api = app.api, !sendingLogs else { return }
        let entries = DeviceLogs.shared.snapshot()
        guard !entries.isEmpty else {
            logStatus = L("diagnostics.empty")
            return
        }
        sendingLogs = true
        logStatus = L("diagnostics.sending")
        Task {
            defer { sendingLogs = false }
            do {
                try await api.sendDeviceLogs(entries)
                logStatus = L("diagnostics.sent")
            } catch let error as APIError where error.status == 404 {
                logStatus = L("diagnostics.unsupported")
            } catch {
                logStatus = L("diagnostics.failed")
            }
        }
    }

    private func binding(_ value: Bool, _ key: String, _ apply: @escaping (inout Prefs, Bool) -> Void) -> Binding<Bool> {
        Binding(get: { value }, set: { new in save(key, .bool(new)) { apply(&$0, new) } })
    }

    /// Shows the change at once and sends just that preference; puts it back if Arc refuses it.
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

/// tvOS Settings' layout: a picture centred in the left half, the list in the right.
struct SettingsLayout<Side: View, Rows: View>: View {
    @ViewBuilder let side: () -> Side
    @ViewBuilder let rows: () -> Rows

    var body: some View {
        HStack(spacing: 60) {
            side()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            rows()
                .frame(width: 860)
        }
        .padding(.trailing, 80)
        .padding(.vertical, 50)
    }
}

/// About: this app's and the server's versions, how this Apple TV reaches it, where the
/// details and pictures come from, and the open source licences.
struct AboutView: View {
    @Environment(AppModel.self) private var app
    @State private var health: Health?

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    var body: some View {
        SettingsLayout {
            VStack(spacing: 18) {
                ArcWordmark(stacked: true).padding(.bottom, 24)
                Text(L("about.for_apple_tv")).font(.title3.weight(.semibold))
                Text(L("settings.version", Self.appVersion)).foregroundStyle(ArcColor.muted)
                // TheTVDB and TMDB ask to be credited where their details and pictures show.
                Text(L("settings.attribution")).font(.caption).foregroundStyle(ArcColor.subtle)
                    .multilineTextAlignment(.center).frame(maxWidth: 620).padding(.top, 30)
            }
        } rows: {
            List {
                Section(L("about.this_app")) {
                    row(L("about.version"), Self.appVersion)
                    row(L("about.player"), EngineChoice.prefersApple ? L("player.engine_apple") : L("player.engine_mpv"))
                }
                Section(L("about.server")) {
                    row(L("about.server_name"), app.serverName ?? health?.name ?? "")
                    row(L("about.server_version"), health.map { $0.version.isEmpty ? "?" : $0.version } ?? "…")
                    row(L("about.api"), health.map { "v\($0.apiVersion)" } ?? "…")
                    row(L("about.address"), app.serverAddress ?? "")
                    if let local = app.onLocalNetwork {
                        row(L("details.connection"), L(local ? "details.connection_local" : "details.connection_remote"))
                    }
                }
                Section(L("about.licences")) {
                    NavigationLink { LicencesView() } label: { Text(L("about.open_source")) }
                }
            }
        }
        .task {
            health = try? await app.api?.health()
        }
    }

    /// A line with its value at the right; focusable, so the list scrolls to it.
    private func row(_ title: String, _ value: String) -> some View {
        Button {} label: { LabeledContent(title, value: value) }
    }
}

/// The open source code in this app and the licence each is under.
struct LicencesView: View {
    private static let parts: [(name: String, licence: String)] = [
        ("Arc for Apple TV", "AGPL-3.0"),
        ("mpv", "GPL-3.0 (as built)"),
        ("FFmpeg", "GPL-3.0 (as built)"),
        ("mpv-build for Apple TV (edde746)", "GPL-3.0"),
        ("libass", "ISC"),
        ("libplacebo", "LGPL-2.1"),
        ("FreeType", "FreeType License"),
        ("HarfBuzz", "MIT"),
        ("FriBidi", "LGPL-2.1"),
    ]

    var body: some View {
        SettingsLayout {
            VStack(spacing: 18) {
                Image(systemName: "doc.text").font(.system(size: 160, weight: .light)).foregroundStyle(.white.opacity(0.85))
                Text(L("about.open_source")).font(.title3.weight(.semibold))
                Text(L("about.licences_note")).font(.caption).foregroundStyle(ArcColor.subtle)
                    .multilineTextAlignment(.center).frame(maxWidth: 620)
            }
        } rows: {
            List {
                ForEach(Self.parts, id: \.name) { part in
                    Button {} label: { LabeledContent(part.name, value: part.licence) }
                }
            }
        }
    }
}
