import ArcKit
import SwiftUI

/// The first screens' frame on iPhone and iPad: Arc's glow behind, the logo, then the screen's
/// own content in a column of readable width that scrolls when the keyboard is up.
struct AuthPage<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ArcWordmark(height: 44)
                content()
            }
            .frame(maxWidth: 480, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 48)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AuthGlow(radius: 520))
    }
}

/// Connect to your Arc server: the address, or a server found on the home network (as the
/// Apple TV's and Android's server screens).
struct MobileServerScreen: View {
    @Environment(AppModel.self) private var app
    @State private var address = ""
    @State private var problem: String?
    @State private var checking = false
    /// Arc servers found on the home network: nil off a home network.
    @State private var found: [FoundServer]? = nil
    @State private var searching = false
    @FocusState private var typing: Bool

    var body: some View {
        AuthPage {
            Text(L("server.title")).font(.title2.weight(.bold)).padding(.top, 32)
            Text(L("server.body")).foregroundStyle(ArcColor.muted).padding(.top, 8)
            TextField(L("server.hint"), text: $address)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($typing)
                .onSubmit(connect)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(ArcColor.surface))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(ArcColor.surface3, lineWidth: 1))
                .padding(.top, 24)
                .accessibilityIdentifier("server.address")
            Group {
                if let problem {
                    Text(problem).foregroundStyle(ArcColor.error)
                } else {
                    Text(L("server.port_note")).foregroundStyle(ArcColor.subtle)
                }
            }
            .font(.footnote)
            .padding(.top, 10)
            Button(action: connect) {
                HStack {
                    if checking { ProgressView().tint(.black) }
                    Text(checking ? L("server.checking") : L("server.connect"))
                }
                .frame(maxWidth: .infinity)
            }
            .arcGlassButton(prominent: true)
            .controlSize(.large)
            .disabled(checking || address.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.top, 20)
            onNetwork.padding(.top, 40)
        }
        .task { await search() }
    }

    @ViewBuilder private var onNetwork: some View {
        if let found {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("server.on_network")).font(.headline)
                ForEach(found) { server in
                    Button { connect(to: server.address) } label: {
                        HStack(spacing: 14) {
                            Image("ArcMark").resizable().scaledToFit().frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(server.name).font(.body.weight(.semibold)).foregroundStyle(ArcColor.foreground)
                                Text(L("server.found_detail", server.address.host ?? ServerAddress.display(server.address), server.version))
                                    .font(.footnote).foregroundStyle(ArcColor.muted)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(ArcColor.subtle)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(ArcColor.surface))
                    }
                    .buttonStyle(.plain)
                    .disabled(checking)
                }
                if searching {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(L("server.looking")).font(.footnote).foregroundStyle(ArcColor.muted)
                    }
                } else if found.isEmpty {
                    Text(L("server.none_found")).font(.footnote).foregroundStyle(ArcColor.muted)
                    Button(L("server.search_again")) { Task { await search() } }.arcGlassButton()
                }
            }
        }
    }

    /// Asks each address on the home network for Arc (arc-media-server `GET /discover`).
    private func search() async {
        guard !searching else { return }
        guard let me = LocalNetwork.ipv4() else {
            found = nil
            ArcLogApp.info("network search skipped: not on a home network")
            return
        }
        found = []
        searching = true
        let started = Date()
        let session = Discovery.quickSession()
        let hosts = Discovery.candidates(address: me.address, prefix: me.prefix)
        let all = await Discovery.scan(hosts: hosts, session: session) { server in
            await MainActor.run {
                guard found?.contains(where: { $0.id == server.id }) == false else { return }
                found?.append(server)
            }
        }
        session.finishTasksAndInvalidate()
        found = all
        searching = false
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        ArcLogApp.info("network search: \(all.count) Arc found of \(hosts.count) addresses in \(ms) ms")
    }

    private func connect() {
        guard let url = ServerAddress.normalize(address) else {
            problem = L("server.invalid")
            return
        }
        connect(to: url)
    }

    private func connect(to url: URL) {
        problem = nil
        checking = true
        typing = false
        Task {
            defer { checking = false }
            do {
                _ = try await app.connect(to: url)
            } catch is AppModel.NotArc {
                problem = L("server.not_arc")
            } catch is UnexpectedAnswer {
                problem = L("server.not_arc")
            } catch {
                ArcLogApp.info("connecting to a server failed: \(type(of: error))")
                problem = L("mobile.server_unreachable")
            }
        }
    }
}

/// Signing in with a code, as on Apple TV (docs/API.md, "On a TV, with a code"): the code is
/// entered in Arc on another device, or in Arc's Link a Device page, which opens here in Safari.
struct MobileSignInScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var code: String?
    @State private var renewed = false
    @State private var problem: String?
    @State private var attempt = 0

    var body: some View {
        AuthPage {
            Text(L("signin.title")).font(.title2.weight(.bold)).padding(.top, 32)
            Text(L("mobile.signin_body")).foregroundStyle(ArcColor.muted).padding(.top, 8)
            Group {
                if let code {
                    HStack(spacing: 10) {
                        ForEach(Array(code.enumerated()), id: \.offset) { _, c in
                            Text(String(c))
                                .font(.system(size: 40, weight: .semibold, design: .rounded))
                                .frame(maxWidth: 64, minHeight: 76)
                                .frame(maxWidth: .infinity)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(ArcColor.surface))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(ArcColor.surface3, lineWidth: 1))
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(code.map(String.init).joined(separator: " ")))
                    .accessibilityIdentifier("signin.code")
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(renewed ? L("signin.expired") : L("signin.waiting")).font(.footnote).foregroundStyle(ArcColor.muted)
                    }
                    .padding(.top, 16)
                } else if problem == nil {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 76)
                }
            }
            .padding(.top, 28)
            if let problem { Text(problem).font(.footnote).foregroundStyle(ArcColor.error).padding(.top, 16) }
            Button {
                if let url = linkPage { openURL(url) }
            } label: {
                Label(L("mobile.signin_open_link"), systemImage: "safari").frame(maxWidth: .infinity)
            }
            .arcGlassButton(prominent: true)
            .controlSize(.large)
            .disabled(code == nil || linkPage == nil)
            .padding(.top, 28)
            Text(L("signin.step_open")).font(.footnote).foregroundStyle(ArcColor.muted).padding(.top, 16)
            HStack(spacing: 12) {
                Button(L("signin.new_code")) { renewed = false; attempt += 1 }.arcGlassButton()
                Button(L("signin.change_server")) { app.changeServer() }.arcGlassButton()
            }
            .padding(.top, 24)
            Text(L("signin.server", app.serverAddress ?? "")).font(.caption).foregroundStyle(ArcColor.subtle).padding(.top, 24)
        }
        .task(id: attempt) { await signIn() }
    }

    /// Arc's Link a Device page on the server (its web app's /link).
    private var linkPage: URL? { app.api?.baseURL.appendingPathComponent("link") }

    private func signIn() async {
        guard let api = app.api else { return }
        code = nil
        problem = nil
        do {
            while !Task.isCancelled {
                let link = try await api.startLink(device: app.deviceName)
                code = link.code
                var failures = 0
                polling: while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(3))
                    do {
                        switch try await api.pollLink(link.poll) {
                        case .waiting: failures = 0
                        case .expired:
                            ArcLogApp.info("sign-in code ran out; asking for a new one")
                            renewed = true
                            break polling
                        case .approved(let token):
                            ArcLogApp.info("signed in with a code")
                            app.signedIn(token: token)
                            return
                        }
                    } catch is CancellationError {
                        return
                    } catch {
                        // A blip in the network shouldn't throw the code away; a long outage should say so.
                        failures += 1
                        if failures >= 5 { throw error }
                    }
                }
            }
        } catch is CancellationError {
        } catch {
            ArcLogApp.warn("sign-in failed: \(type(of: error))")
            code = nil
            problem = (error as? APIError)?.message ?? L("signin.failed")
        }
    }
}

/// Who's watching? The profiles in a grid of round avatars, as the web's and the TV's picker; a
/// profile with a PIN asks for it with the number keypad.
struct MobileProfilesScreen: View {
    @Environment(AppModel.self) private var app
    @State private var profiles: [Profile] = []
    @State private var loading = true
    @State private var problem: String?
    @State private var pinFor: Profile?

    var body: some View {
        AuthPage {
            Text(L("profiles.title")).font(.title2.weight(.bold)).padding(.top, 32)
            if let name = app.serverName { Text(name).foregroundStyle(ArcColor.muted).padding(.top, 4) }
            if loading {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 48)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 140), spacing: 20)], spacing: 24) {
                    ForEach(profiles) { profile in
                        Button { choose(profile) } label: {
                            VStack(spacing: 10) {
                                Avatar(profile: profile, size: 88)
                                    .overlay(alignment: .bottomTrailing) {
                                        if profile.hasPin {
                                            Image(systemName: "lock.fill")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(ArcColor.muted)
                                                .frame(width: 28, height: 28)
                                                .background(Circle().fill(ArcColor.surface3))
                                                .padding(3)
                                                .background(Circle().fill(ArcColor.background))
                                        }
                                    }
                                Text(profile.name).font(.subheadline.weight(.semibold)).foregroundStyle(ArcColor.foreground).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(profile.hasPin ? "\(profile.name), \(L("profiles.locked"))" : profile.name))
                    }
                }
                .padding(.top, 32)
            }
            if let problem { Text(problem).font(.footnote).foregroundStyle(ArcColor.error).padding(.top, 24) }
            Button(L("profiles.sign_out")) { Task { await app.signOut() } }
                .arcGlassButton()
                .padding(.top, 40)
        }
        .sheet(item: $pinFor) { profile in
            MobilePinSheet(profile: profile) { pin in await submit(profile, pin: pin) }
                .presentationDetents([.medium, .large])
        }
        .task { await load() }
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
        problem = nil
        if profile.hasPin {
            pinFor = profile
        } else {
            Task { _ = await submit(profile, pin: nil) }
        }
    }

    /// Chooses the profile; false when the PIN was wrong (the sheet asks again).
    private func submit(_ profile: Profile, pin: String?) async -> Bool {
        guard let api = app.api else { return true }
        do {
            let chosen = try await api.chooseProfile(id: profile.id, pin: pin)
            ArcLogApp.info("profile chosen")
            pinFor = nil
            app.chose(chosen)
            return true
        } catch let error as APIError where error.status == 401 && error.needs == nil {
            pinFor = nil
            app.tokenRefused()
        } catch let error as APIError where error.needs == "pin" && pin != nil {
            ArcLogApp.debug("profile PIN refused")
            return false
        } catch let error as APIError {
            pinFor = nil
            problem = error.needs == "password" ? L("profiles.needs_password") : error.needs == "pin" ? L("profiles.wrong_pin") : error.message
        } catch {
            pinFor = nil
            problem = L("common.unreachable")
        }
        return true
    }
}

/// A profile's PIN: four boxes over the number keypad. The fourth digit checks it at once, as
/// Plex's; a wrong PIN shakes the boxes and empties them.
struct MobilePinSheet: View {
    let profile: Profile
    let submit: (String) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var digits = ""
    @State private var wrong = false
    @State private var checking = false
    @State private var shake: CGFloat = 0
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Avatar(profile: profile, size: 72)
                Text(profile.name).font(.title3.weight(.semibold)).padding(.top, 12)
                Text(L("pin.enter")).foregroundStyle(ArcColor.muted).padding(.top, 4)
                ZStack {
                    // The keypad types into this; the boxes show what's typed.
                    TextField("", text: $digits)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($typing)
                        .opacity(0.01)
                        .frame(width: 1, height: 1)
                        .accessibilityIdentifier("pin.field")
                    HStack(spacing: 14) {
                        ForEach(0..<4, id: \.self) { box($0) }
                    }
                    .offset(x: shake)
                    .contentShape(Rectangle())
                    .onTapGesture { typing = true }
                }
                .padding(.top, 28)
                Text(wrong ? L("pin.wrong") : " ").font(.footnote).foregroundStyle(ArcColor.error).padding(.top, 14)
                if checking { ProgressView().padding(.top, 8) }
                Spacer(minLength: 0)
            }
            .padding(.top, 24)
            .frame(maxWidth: .infinity)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common.cancel")) { dismiss() }
                }
            }
        }
        .onAppear { typing = true }
        .onChange(of: digits) { _, now in
            let clean = String(now.filter(\.isNumber).prefix(4))
            if clean != now { digits = clean; return }
            if !clean.isEmpty { wrong = false }
            if clean.count == 4 { check(clean) }
        }
    }

    private func box(_ i: Int) -> some View {
        let next = i == digits.count && !wrong
        let ring = wrong ? ArcColor.error : next ? ArcColor.foreground : ArcColor.surface3
        return ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ArcColor.surface)
            RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(ring, lineWidth: next ? 2 : 1)
            if i < digits.count { Circle().fill(ArcColor.foreground).frame(width: 12, height: 12) }
        }
        .frame(width: 56, height: 64)
    }

    private func check(_ pin: String) {
        guard !checking else { return }
        checking = true
        Task {
            let accepted = await submit(pin)
            checking = false
            guard !accepted else { return }
            wrong = true
            digits = ""
            for x: CGFloat in [-14, 14, -8, 8, 0] {
                withAnimation(.linear(duration: 0.06)) { shake = x }
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
    }
}
