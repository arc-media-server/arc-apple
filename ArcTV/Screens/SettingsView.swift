import ArcKit
import SwiftUI

/// Settings: the profile's playback preferences (the same ones as Arc's Settings on the web, so
/// they follow the profile to every app), switching profile, the server, and about.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var prefs: Prefs?
    @State private var problem: String?
    @State private var confirmSignOut = false

    var body: some View {
        HStack(alignment: .top, spacing: 80) {
            VStack(alignment: .leading, spacing: 24) {
                Text(L("tab.settings")).font(.title2.weight(.semibold))
                if let profile = app.profile {
                    HStack(spacing: 20) {
                        Avatar(profile: profile, size: 120)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(profile.name).font(.headline)
                            if let name = app.serverName { Text(name).foregroundStyle(ArcColor.muted) }
                            if let address = app.serverAddress { Text(address).font(.caption).foregroundStyle(ArcColor.subtle) }
                        }
                    }
                }
                Text(L("settings.attribution")).font(.caption).foregroundStyle(ArcColor.subtle).frame(maxWidth: 560, alignment: .leading)
                Text(L("settings.version", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"))
                    .font(.caption).foregroundStyle(ArcColor.subtle)
            }
            .frame(width: 600, alignment: .leading)
            List {
                Section(L("settings.playback")) {
                    if let prefs {
                        Toggle(L("settings.auto_play"), isOn: binding(prefs.autoPlay, "auto_play") { $0.autoPlay = $1 })
                        Toggle(L("settings.auto_skip"), isOn: binding(prefs.autoSkip, "auto_skip") { $0.autoSkip = $1 })
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
                }
                Section(L("settings.account")) {
                    Button(L("settings.switch_profile")) { app.switchProfile() }
                    Button(L("profiles.sign_out")) { confirmSignOut = true }
                    Button(L("signin.change_server")) { app.changeServer() }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 80)
        .padding(.vertical, 40)
        .task { await load() }
        .confirmationDialog(L("settings.sign_out_title"), isPresented: $confirmSignOut) {
            Button(L("profiles.sign_out"), role: .destructive) { Task { await app.signOut() } }
            Button(L("common.cancel"), role: .cancel) {}
        } message: {
            Text(L("settings.sign_out_body"))
        }
    }

    private func binding(_ value: Bool, _ key: String, _ apply: @escaping (inout Prefs, Bool) -> Void) -> Binding<Bool> {
        Binding(get: { value }, set: { new in save(key, .bool(new)) { apply(&$0, new) } })
    }

    /// Shows the change at once and sends just that preference; puts it back if Arc refuses it.
    private func save(_ key: String, _ value: JSONValue, _ apply: (inout Prefs) -> Void) {
        guard var changed = prefs, let api = app.api else { return }
        let before = prefs
        apply(&changed)
        prefs = changed
        problem = nil
        Task {
            do {
                prefs = try await api.updatePrefs([key: value])
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
