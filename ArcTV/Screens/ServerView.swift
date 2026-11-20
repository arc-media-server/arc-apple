import ArcKit
import SwiftUI

/// Connect to your Arc server: the address you use in a browser.
struct ServerView: View {
    @Environment(AppModel.self) private var app
    @State private var address = ""
    @State private var problem: String?
    @State private var checking = false
    /// Arc servers found on the home network (as Android's server screen): nil off a home network.
    @State private var found: [FoundServer]? = nil
    @State private var searching = false
    @FocusState private var focus: String?

    var body: some View {
        VStack(spacing: 32) {
            ArcWordmark()
            Text(L("server.title")).font(.title2.weight(.semibold))
            Text(L("server.body")).foregroundStyle(ArcColor.muted)
            TextField(L("server.hint"), text: $address)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(width: 900)
                .focused($focus, equals: "address")
                .onSubmit(connect)
            Text(L("server.port_note")).font(.caption).foregroundStyle(ArcColor.subtle)
            if let problem {
                Text(problem).foregroundStyle(ArcColor.error).multilineTextAlignment(.center).frame(maxWidth: 900)
            }
            Button(action: connect) {
                Text(checking ? L("server.checking") : L("server.connect")).frame(minWidth: 320)
            }
            .arcGlassButton(prominent: true)
            .disabled(checking)
            if let found { onNetwork(found) }
        }
        .padding(80)
        .task { await search() }
    }

    /// On your network: each Arc that answered, then Search Again when none did.
    @ViewBuilder private func onNetwork(_ servers: [FoundServer]) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                Text(L("server.on_network")).font(.headline)
                if searching { ProgressView() }
            }
            ForEach(servers) { server in
                Button { connect(to: server.address) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(server.name).font(.body.weight(.semibold))
                        Text(L("server.found_detail", server.address.host ?? ServerAddress.display(server.address), server.version))
                            .font(.caption).foregroundStyle(ArcColor.muted)
                    }
                    .frame(width: 600, alignment: .leading)
                }
                .arcGlassButton()
                .focused($focus, equals: server.id)
                .disabled(checking)
            }
            if servers.isEmpty && searching {
                Text(L("server.looking")).font(.callout).foregroundStyle(ArcColor.muted)
            } else if servers.isEmpty {
                Text(L("server.none_found")).font(.callout).foregroundStyle(ArcColor.muted)
                Button(L("server.search_again")) { Task { await search() } }.arcGlassButton()
            }
        }
        .focusSection()
    }

    /// Asks each address on the Apple TV's home network for Arc (arc-media-server `GET /discover`).
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
                // The first server takes the focus, so one press connects (as Plex lists its
                // servers), unless an address is being typed.
                if found?.count == 1 && address.isEmpty && focus != "address" { focus = server.id }
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
                problem = L("server.unreachable")
            }
        }
    }
}

/// Arc's logo (arc-media-server `docs/brand`, chosen 13 November): white, no colour. The main
/// logo (the TV beside "arc / MEDIA SERVER") tops the server, sign-in and profile screens, as on
/// Android; the stacked one (the TV above the name) is for About.
struct ArcWordmark: View {
    var stacked = false

    var body: some View {
        Image(stacked ? "ArcLogoStacked" : "ArcLogo")
            .resizable()
            .scaledToFit()
            .frame(height: stacked ? 220 : 88)
            .accessibilityLabel(Text(L("about.product_name")))
    }
}
