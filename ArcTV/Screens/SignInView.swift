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
        // As Android's sign-in screen: the steps on the left, the code large on the right.
        HStack(alignment: .center, spacing: 128) {
            VStack(alignment: .leading, spacing: 0) {
                ArcWordmark()
                Text(L("signin.title")).font(.title.weight(.semibold)).padding(.top, 40)
                VStack(alignment: .leading, spacing: 28) {
                    step(1, L("signin.step_open"))
                    step(2, L("signin.step_link", address + "/link"))
                    step(3, L("signin.step_code"))
                }
                .padding(.top, 56)
                if let problem { Text(problem).font(.callout).foregroundStyle(ArcColor.error).padding(.top, 40) }
                HStack(spacing: 28) {
                    Button(L("signin.new_code")) { renewed = false; attempt += 1 }.arcGlassButton()
                    Button(L("signin.change_server")) { app.changeServer() }.arcGlassButton()
                }
                .padding(.top, 72)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 0) {
                if let code {
                    HStack(spacing: 24) {
                        ForEach(Array(code.enumerated()), id: \.offset) { _, c in
                            Text(String(c))
                                .font(.system(size: 112, weight: .semibold))
                                .frame(width: 168, height: 216)
                                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(ArcColor.surface))
                                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(ArcColor.surface3, lineWidth: 4))
                        }
                    }
                    HStack(spacing: 20) {
                        ProgressView()
                        Text(renewed ? L("signin.expired") : L("signin.waiting")).foregroundStyle(ArcColor.muted)
                    }
                    .font(.callout)
                    .padding(.top, 56)
                } else if problem == nil {
                    ProgressView()
                }
                Text(L("signin.server", address)).font(.caption).foregroundStyle(ArcColor.subtle).padding(.top, 24)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 112)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AuthGlow())
        .task(id: attempt) { await signIn() }
    }

    /// The server's address as typed, without http:// or https://.
    private var address: String {
        (app.serverAddress ?? "").replacingOccurrences(of: "http://", with: "").replacingOccurrences(of: "https://", with: "")
    }

    /// A numbered step: its number in a small grey circle, then what to do.
    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 28) {
            Text(String(number))
                .font(.callout.weight(.semibold))
                .frame(width: 56, height: 56)
                .background(Circle().fill(ArcColor.surface3))
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
        }
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
