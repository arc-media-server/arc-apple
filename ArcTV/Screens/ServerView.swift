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
        // As Android's server screen: one column, left-aligned, in the middle of the screen over
        // Arc's soft glow: the logo, the heading and a line, the address with Connect beside it,
        // a line under them (connecting, what went wrong, or the port note), then the servers
        // found on the network.
        VStack(alignment: .leading, spacing: 0) {
            ArcWordmark()
            Text(L("server.title")).font(.title.weight(.semibold)).padding(.top, 40)
            Text(L("server.body")).font(.callout).foregroundStyle(ArcColor.muted).padding(.top, 16)
            HStack(spacing: 32) {
                TextField(L("server.hint"), text: $address)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: "address")
                    .onSubmit(connect)
                Button(action: connect) {
                    Text(checking ? L("server.checking") : L("server.connect")).frame(minWidth: 200)
                }
                .arcGlassButton(prominent: true)
                .disabled(checking)
            }
            .padding(.top, 56)
            Group {
                if checking {
                    HStack(spacing: 20) {
                        ProgressView()
                        Text(L("server.checking")).foregroundStyle(ArcColor.muted)
                    }
                } else if let problem {
                    Text(problem).foregroundStyle(ArcColor.error)
                } else {
                    Text(L("server.port_note")).foregroundStyle(ArcColor.subtle)
                }
            }
            .font(.callout)
            .padding(.top, 28)
            if let found { onNetwork(found).padding(.top, 56) }
        }
        .frame(width: 1120, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AuthGlow())
        .task { await search() }
    }

    /// On your network: each Arc that answered, then Search Again when none did.
    @ViewBuilder private func onNetwork(_ servers: [FoundServer]) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 24) {
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
                    .frame(width: 1040, alignment: .leading)
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

