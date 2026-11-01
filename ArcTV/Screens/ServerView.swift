import ArcKit
import SwiftUI

/// Connect to your Arc server: the address you use in a browser.
struct ServerView: View {
    @Environment(AppModel.self) private var app
    @State private var address = ""
    @State private var problem: String?
    @State private var checking = false

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
        }
        .padding(80)
    }

    private func connect() {
        guard let url = ServerAddress.normalize(address) else {
            problem = L("server.invalid")
            return
        }
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

/// Arc's name in the logo's teal gradient.
struct ArcWordmark: View {
    var body: some View {
        Text("Arc")
            .font(.system(size: 76, weight: .bold, design: .rounded))
            .foregroundStyle(ArcColor.accentGradient)
            .accessibilityHidden(true)
    }
}
