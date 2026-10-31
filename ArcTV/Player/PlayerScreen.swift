import ArcKit
import SwiftUI

/// The player: the picture, a spinner while it waits, and Arc's own controls (title, timeline,
/// times). Play/Pause and the touch surface's click toggle playing, left and right skip 10
/// seconds, and Back hides the controls or closes the player.
struct PlayerScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let request: PlayRequest

    @State private var model: PlayerModel?
    @State private var controls = true
    @State private var hideTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let model {
                EngineSurface(engine: model.engine).ignoresSafeArea()
                if let problem = model.problem {
                    ProblemPane(message: problem, retry: { model.retry() }, close: { dismiss() })
                } else {
                    if model.loading || model.waiting { ProgressView().scaleEffect(1.6) }
                    PlayerControls(model: model).opacity(controls ? 1 : 0).animation(.easeInOut(duration: 0.25), value: controls)
                }
            }
        }
        .focusable(model?.problem == nil)
        .focused($focused)
        .onMoveCommand { direction in
            switch direction {
            case .left: model?.seek(by: -10_000)
            case .right: model?.seek(by: 10_000)
            default: break
            }
            showControls()
        }
        .onPlayPauseCommand { model?.togglePlay(); showControls() }
        .onTapGesture { model?.togglePlay(); showControls() }
        .onExitCommand {
            if controls && model?.playing == true {
                controls = false
            } else {
                dismiss()
            }
        }
        .onAppear {
            guard model == nil, let api = app.api else { return }
            let m = PlayerModel(api: api, item: request.item, startMs: request.startMs, engine: AVPlayerEngine()) { app.tokenRefused() }
            model = m
            m.start()
            focused = true
            showControls()
        }
        .onDisappear {
            hideTask?.cancel()
            model?.close()
        }
        .onChange(of: model?.ended ?? false) { _, ended in if ended { dismiss() } }
    }

    private func showControls() {
        controls = true
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled && model?.playing == true { controls = false }
        }
    }
}

private struct EngineSurface: UIViewRepresentable {
    let engine: PlaybackEngine
    func makeUIView(context: Context) -> UIView { engine.view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// The title, the timeline and the times, over a gradient at the bottom.
private struct PlayerControls: View {
    let model: PlayerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                if model.item.isEpisode {
                    Text(model.item.seriesTitle ?? "").font(.title3.weight(.semibold))
                    Text(L("card.episode", model.item.seasonNumber ?? 0, model.item.episodeNumber ?? 0, model.item.title)).foregroundStyle(ArcColor.muted)
                } else {
                    Text(model.item.title).font(.title3.weight(.semibold))
                }
            }
            GeometryReader { geo in
                let fraction = model.durationMs > 0 ? min(1, Double(model.positionMs) / Double(model.durationMs)) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule().fill(ArcColor.accent).frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 8)
            HStack {
                Image(systemName: model.playing ? "pause.fill" : "play.fill")
                Text(time(model.positionMs)).monospacedDigit()
                Spacer()
                Text("-" + time(max(0, model.durationMs - model.positionMs))).monospacedDigit()
            }
            .font(.callout)
            .foregroundStyle(ArcColor.muted)
        }
        .padding(.horizontal, 90)
        .padding(.bottom, 60)
        .background(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                .frame(height: 420)
                .ignoresSafeArea()
        }
    }

    private func time(_ ms: Int64) -> String {
        let s = Int(ms / 1000)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

private struct ProblemPane: View {
    let message: String
    let retry: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Text(L("player.failed_title")).font(.title3.weight(.semibold))
            Text(message).foregroundStyle(ArcColor.muted).multilineTextAlignment(.center).frame(maxWidth: 900)
            HStack(spacing: 40) {
                Button(L("common.retry"), action: retry)
                Button(L("common.close"), action: close)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.85))
    }
}
