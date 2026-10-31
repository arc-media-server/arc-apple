import ArcKit
import SwiftUI

/// The TV sign-in code flow (docs/API.md, "On a TV, with a code"): show a code, ask every few
/// seconds whether it's been entered in Arc on a phone or computer, and get a new one when it
/// runs out.
struct SignInView: View {
    @Environment(AppModel.self) private var app
    @State private var code: String?
    @State private var renewed = false
    @State private var problem: String?
    @State private var attempt = 0

    var body: some View {
        VStack(spacing: 28) {
            ArcWordmark()
            Text(L("signin.title")).font(.title2.weight(.semibold))
            VStack(alignment: .leading, spacing: 16) {
                Text(L("signin.step_open"))
                Text(L("signin.step_link", (app.serverAddress ?? "").replacingOccurrences(of: "http://", with: "").replacingOccurrences(of: "https://", with: "") + "/link"))
                Text(L("signin.step_code"))
            }
            .foregroundStyle(ArcColor.muted)
            if let code {
                HStack(spacing: 16) {
                    ForEach(Array(code.enumerated()), id: \.offset) { _, c in
                        Text(String(c))
                            .font(.system(size: 64, weight: .semibold, design: .monospaced))
                            .frame(width: 96, height: 120)
                            .background(ArcColor.surface2, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                Text(renewed ? L("signin.expired") : L("signin.waiting")).foregroundStyle(ArcColor.subtle)
            } else if problem == nil {
                ProgressView()
            }
            if let problem { Text(problem).foregroundStyle(ArcColor.error) }
            HStack(spacing: 40) {
                Button(L("signin.new_code")) { renewed = false; attempt += 1 }
                Button(L("signin.change_server")) { app.changeServer() }
            }
            Text(L("signin.server", app.serverAddress ?? "")).font(.caption).foregroundStyle(ArcColor.subtle)
        }
        .padding(80)
        .task(id: attempt) { await signIn() }
    }

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
                            ArcLogApp.info("signed in with a TV code")
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
            ArcLogApp.warn("TV sign-in failed: \(type(of: error))")
            code = nil
            problem = (error as? APIError)?.message ?? L("signin.failed")
        }
    }
}
