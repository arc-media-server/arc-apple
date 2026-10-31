import ArcKit
import SwiftUI

/// Who's watching? The profiles as the web's picker shows them, the server's name under the
/// title, a PIN asked for when a profile has one.
struct ProfilesView: View {
    @Environment(AppModel.self) private var app
    @State private var profiles: [Profile] = []
    @State private var loading = true
    @State private var problem: String?
    @State private var pinFor: Profile?
    @State private var pin = ""

    var body: some View {
        VStack(spacing: 48) {
            ArcWordmark()
            VStack(spacing: 8) {
                Text(L("profiles.title")).font(.title2.weight(.semibold))
                if let name = app.serverName { Text(name).foregroundStyle(ArcColor.muted) }
            }
            if loading {
                ProgressView()
            } else {
                HStack(spacing: 56) {
                    ForEach(profiles) { profile in
                        Button { choose(profile) } label: {
                            VStack(spacing: 20) {
                                Avatar(profile: profile, size: 200)
                                Text(profile.name).font(.headline)
                                if profile.hasPin {
                                    Label(L("profiles.locked"), systemImage: "lock.fill").font(.caption).foregroundStyle(ArcColor.muted)
                                }
                            }
                            .padding(24)
                        }
                        .buttonStyle(.card)
                    }
                }
            }
            if let problem { Text(problem).foregroundStyle(ArcColor.error).multilineTextAlignment(.center).frame(maxWidth: 1100) }
            Button(L("profiles.sign_out")) { Task { await app.signOut() } }
        }
        .padding(80)
        .task { await load() }
        .alert(L("profiles.pin_title", pinFor?.name ?? ""), isPresented: Binding(get: { pinFor != nil }, set: { if !$0 { pinFor = nil } })) {
            SecureField(L("profiles.pin_hint"), text: $pin).keyboardType(.numberPad)
            Button(L("common.ok")) {
                if let p = pinFor { submit(p, pin: pin) }
                pin = ""
            }
            Button(L("common.cancel"), role: .cancel) { pin = "" }
        }
    }

    private func load() async {
        guard let api = app.api else { return }
        loading = true
        defer { loading = false }
        do {
            let status = try await api.authStatus()
            if !status.signedIn {
                app.tokenRefused()
                return
            }
            profiles = status.profiles
        } catch let error as APIError where error.status == 401 {
            app.tokenRefused()
        } catch {
            problem = L("common.unreachable")
        }
    }

    private func choose(_ profile: Profile) {
        if profile.hasPin {
            pin = ""
            pinFor = profile
        } else {
            submit(profile, pin: nil)
        }
    }

    private func submit(_ profile: Profile, pin: String?) {
        guard let api = app.api else { return }
        problem = nil
        Task {
            do {
                let chosen = try await api.chooseProfile(id: profile.id, pin: pin)
                ArcLogApp.info("profile chosen")
                app.chose(chosen)
            } catch let error as APIError where error.status == 401 && error.needs == nil {
                app.tokenRefused()
            } catch let error as APIError {
                problem = error.needs == "password" ? L("profiles.needs_password") : error.needs == "pin" ? L("profiles.wrong_pin") : error.message
            } catch {
                problem = L("common.unreachable")
            }
        }
    }
}

/// A profile's picture: its initial on its colour (web/src/components/Avatar.tsx).
struct Avatar: View {
    let profile: Profile
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(LinearGradient(colors: ArcColor.profile(profile.color), startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                Text(profile.name.trimmingCharacters(in: .whitespaces).prefix(1).uppercased().isEmpty ? "?" : String(profile.name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}
