import ArcKit
import SwiftUI

/// Plays a trailer or other extra: the picture, Play/Pause, left and right to move 10 seconds,
/// Back to close. It goes through a cast link, as Apple's player can't send the sign-in header.
struct ExtraPlayerScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let extra: Extra
    @State private var engine = AVPlayerEngine()
    @State private var loading = true
    @State private var problem: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ExtraSurface(engine: engine).ignoresSafeArea()
            if loading && problem == nil { ProgressView().scaleEffect(1.6) }
            if let problem {
                VStack(spacing: 24) {
                    Text(problem).foregroundStyle(ArcColor.muted).multilineTextAlignment(.center).frame(maxWidth: 900)
                    Button(L("common.close")) { dismiss() }.arcGlassButton()
                }
            }
            Color.clear
                .contentShape(Rectangle())
                .focusable()
                .onMoveCommand { direction in
                    switch direction {
                    case .left: engine.seek(to: max(0, engine.currentSeconds - 10))
                    case .right: engine.seek(to: engine.currentSeconds + 10)
                    default: break
                    }
                }
        }
        .onPlayPauseCommand { engine.isPlaying ? engine.pause() : engine.play() }
        .onExitCommand { dismiss() }
        .onAppear {
            engine.onEvent = { event in
                switch event {
                case .ready: loading = false
                case .ended: dismiss()
                case .failed(let reason):
                    ArcLogApp.warn("an extra didn't play: \(reason)")
                    problem = L("player.failed")
                case .waiting: break
                }
            }
            Task {
                guard let api = app.api else { return }
                do {
                    let url = try await api.castLink(for: extra.streamUrl)
                    ArcLogApp.info("playing an extra (\(extra.kind))")
                    engine.load(url, headers: [:], startSeconds: 0)
                } catch {
                    ArcLogApp.warn("an extra's link failed: \(type(of: error))")
                    problem = L("player.failed")
                }
            }
        }
        .onDisappear { engine.stop() }
    }
}

private struct ExtraSurface: UIViewRepresentable {
    let engine: PlaybackEngine
    func makeUIView(context: Context) -> UIView { engine.view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
