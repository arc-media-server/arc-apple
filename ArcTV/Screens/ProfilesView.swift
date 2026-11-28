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
    /// The PIN was wrong: the boxes shake and say so, then take the next try.
    @State private var wrongPin = false
    @State private var checkingPin = false
    /// Focus starts on the first profile, as Plex's picker; otherwise tvOS can land on Sign Out,
    /// and the first press of Select would sign the Apple TV out.
    @FocusState private var focused: String?

    var body: some View {
        ZStack {
            if let profile = pinFor {
                PinEntry(profile: profile, wrong: $wrongPin, checking: checkingPin,
                         onEntered: { submit(profile, pin: $0) }, onBack: { pinFor = nil })
            } else {
                picker
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AuthGlow())
        .task { await load() }
    }

    private var picker: some View {
        VStack(spacing: 48) {
            ArcWordmark()
            VStack(spacing: 8) {
                Text(L("profiles.title")).font(.title2.weight(.semibold))
                if let name = app.serverName { Text(name).foregroundStyle(ArcColor.muted) }
            }
            if loading {
                ProgressView()
            } else {
                // Round avatars with no card, as Android's and the web's picker: a white ring and
                // a little growth on focus, a lock badge on the rim for a profile with a PIN, and
                // the name under it, white when focused.
                HStack(alignment: .top, spacing: 64) {
                    ForEach(profiles) { profile in
                        VStack(spacing: 28) {
                            Button { choose(profile) } label: {
                                Avatar(profile: profile, size: 224)
                            }
                            .buttonStyle(ProfileCircleStyle(locked: profile.hasPin))
                            .focused($focused, equals: profile.id)
                            .accessibilityLabel(Text(profile.hasPin ? "\(profile.name), \(L("profiles.locked"))" : profile.name))
                            Text(profile.name).font(.headline).lineLimit(1)
                                .foregroundStyle(focused == profile.id ? ArcColor.foreground : ArcColor.muted)
                                .animation(.easeOut(duration: 0.15), value: focused)
                        }
                        .frame(width: 256)
                    }
                }
                .defaultFocus($focused, profiles.first?.id)
            }
            if let problem { Text(problem).foregroundStyle(ArcColor.error).multilineTextAlignment(.center).frame(maxWidth: 1100) }
            Button(L("profiles.sign_out")) { Task { await app.signOut() } }.arcGlassButton()
        }
        .padding(80)
        // Sign Out is the only thing on screen while the profiles load, so it takes the focus:
        // move it to the first profile once they appear.
        .onChange(of: loading) { _, now in
            if !now, focused == nil { Task { @MainActor in focused = profiles.first?.id } }
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
            problem = nil
            wrongPin = false
            pinFor = profile
        } else {
            submit(profile, pin: nil)
        }
    }

    private func submit(_ profile: Profile, pin: String?) {
        guard let api = app.api else { return }
        problem = nil
        if pin != nil { checkingPin = true }
        Task {
            defer { checkingPin = false }
            do {
                let chosen = try await api.chooseProfile(id: profile.id, pin: pin)
                ArcLogApp.info("profile chosen")
                app.chose(chosen)
            } catch let error as APIError where error.status == 401 && error.needs == nil {
                app.tokenRefused()
            } catch let error as APIError where error.needs == "pin" && pinFor != nil {
                // A wrong PIN: the boxes shake and empty for another try, as Plex's.
                ArcLogApp.debug("profile PIN refused")
                wrongPin = true
            } catch let error as APIError {
                pinFor = nil
                problem = error.needs == "password" ? L("profiles.needs_password") : error.needs == "pin" ? L("profiles.wrong_pin") : error.message
            } catch {
                pinFor = nil
                problem = L("common.unreachable")
            }
        }
    }
}

/// Arc's PIN step, as the web's and Android's: the profile's picture and name, "Enter your PIN"
/// and four boxes (the next one ringed in white), with a number pad beside them, since the remote
/// has no number keys. The fourth digit checks it at once, as Plex does; a wrong PIN shakes the
/// boxes and empties them. Back (or Profiles) returns to the profiles.
struct PinEntry: View {
    let profile: Profile
    @Binding var wrong: Bool
    let checking: Bool
    let onEntered: (String) -> Void
    let onBack: () -> Void
    @State private var digits = ""
    @State private var shake: CGFloat = 0
    @FocusState private var key: String?

    var body: some View {
        HStack(alignment: .center, spacing: 192) {
            VStack(spacing: 0) {
                Avatar(profile: profile, size: 192)
                Text(profile.name).font(.title2.weight(.semibold)).padding(.top, 32)
                Text(L("pin.enter")).font(.callout).foregroundStyle(ArcColor.muted).padding(.top, 8)
                HStack(spacing: 24) {
                    ForEach(0..<4, id: \.self) { i in box(i) }
                }
                .offset(x: shake)
                .padding(.top, 48)
                Text(wrong ? L("pin.wrong") : " ").font(.callout).foregroundStyle(ArcColor.error).padding(.top, 24)
                Button(action: onBack) { Label(L("pin.back"), systemImage: "chevron.left") }
                    .arcGlassButton()
                    .padding(.top, 32)
            }
            VStack(spacing: 20) {
                ForEach(["123", "456", "789", " 0<"], id: \.self) { row in
                    HStack(spacing: 20) {
                        ForEach(Array(row), id: \.self) { k in pad(k) }
                    }
                }
            }
            .focusSection()
        }
        .defaultFocus($key, "5")
        .onAppear { key = "5" }
        .onExitCommand(perform: onBack)
        .onChange(of: wrong) { _, now in
            guard now else { return }
            digits = ""
            Task { @MainActor in
                for x: CGFloat in [-20, 20, -12, 12, 0] {
                    withAnimation(.linear(duration: 0.06)) { shake = x }
                    try? await Task.sleep(for: .milliseconds(60))
                }
            }
        }
    }

    private func box(_ i: Int) -> some View {
        let next = i == digits.count && !wrong
        let ring = wrong ? ArcColor.error : next ? ArcColor.foreground : ArcColor.foreground.opacity(0.08)
        return ZStack {
            // Liquid Glass, as the pad's keys and Arc's other controls.
            GlassFill(shape: RoundedRectangle(cornerRadius: 32, style: .continuous))
            RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(ring, lineWidth: next ? 4 : 2)
            if i < digits.count { Text("•").font(.system(size: 52)) }
        }
        .frame(width: 112, height: 112)
    }

    @ViewBuilder private func pad(_ k: Character) -> some View {
        switch k {
        case " ":
            Color.clear.frame(width: 120, height: 120)
        case "<":
            Button { if !digits.isEmpty { digits.removeLast() } } label: {
                Image(systemName: "delete.left").font(.system(size: 40, weight: .medium))
                    .accessibilityLabel(Text(L("pin.delete")))
            }
            .buttonStyle(PadKeyStyle())
            .focused($key, equals: "<")
        default:
            Button { type(k) } label: { Text(String(k)).font(.system(size: 48, weight: .semibold)) }
                .buttonStyle(PadKeyStyle())
                .focused($key, equals: String(k))
        }
    }

    private func type(_ k: Character) {
        guard !checking, digits.count < 4 else { return }
        if wrong { wrong = false }
        digits.append(k)
        if digits.count == 4 { onEntered(digits) }
    }
}

/// A profile's avatar on the picker, as Android's: on focus a white ring and a 1.06 grow; a
/// PIN's lock sits on the rim, moving out with the grow so it stays on the edge.
struct ProfileCircleStyle: ButtonStyle {
    let locked: Bool
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(8)
            .overlay(Circle().stroke(ArcColor.foreground, lineWidth: 8).opacity(isFocused ? 1 : 0))
            .overlay(alignment: .bottomTrailing) {
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(ArcColor.muted)
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(ArcColor.surface3))
                        .padding(8)
                        .background(Circle().fill(ArcColor.background))
                        .offset(x: isFocused ? 6 : 0, y: isFocused ? 6 : 0)
                        .accessibilityHidden(true)
                }
            }
            .scaleEffect(isFocused ? 1.06 : configuration.isPressed ? 0.96 : 1)
            .shadow(color: .black.opacity(isFocused ? 0.4 : 0), radius: 16, y: 10)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

/// A key of the PIN pad: Liquid Glass, white with black when it has the focus, as Android's.
struct PadKeyStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isFocused ? ArcColor.background : ArcColor.foreground)
            .frame(width: 120, height: 120)
            .background {
                if isFocused {
                    RoundedRectangle(cornerRadius: 32, style: .continuous).fill(ArcColor.foreground)
                } else {
                    GlassFill(shape: RoundedRectangle(cornerRadius: 32, style: .continuous))
                }
            }
            .scaleEffect(isFocused ? 1.08 : configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

