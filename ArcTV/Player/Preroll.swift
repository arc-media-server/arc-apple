import ArcKit
import SwiftUI

/// Plays the pre-roll videos chosen in Arc's Settings before a film (the web's Player.tsx), then
/// the film's player. Pre-rolls never stand in the way: a clip that fails moves on, and a list
/// that fails or takes over 3 seconds plays the film without them. Skip (focused) moves to the
/// next clip or the film; Back leaves the player, as everywhere.
struct PrerollGate<Player: View>: View {
    @Environment(AppModel.self) private var app
    @Environment(Browse.self) private var browse
    let request: PlayRequest
    @ViewBuilder let player: () -> Player
    @State private var clips: [PrerollClip] = []
    @State private var index = 0
    @State private var done = false
    @State private var engine = AVPlayerEngine()
    @FocusState private var skipFocused: Bool

    var body: some View {
        if done {
            player()
        } else {
            ZStack(alignment: .bottomTrailing) {
                Color.black.ignoresSafeArea()
                ExtraSurface(engine: engine).ignoresSafeArea()
                if !clips.isEmpty {
                    Button(L("player.skip_preroll")) { next() }
                        .arcGlassButton()
                        .focused($skipFocused)
                        .padding(60)
                }
            }
            .onExitCommand {
                engine.stop()
                browse.playing = nil
            }
            .task { await start() }
        }
    }

    private func start() async {
        guard request.wantsPreroll, let api = app.api else { done = true; return }
        let itemId = request.item.id
        let list: [PrerollClip]? = await withTaskGroup(of: [PrerollClip]?.self) { group in
            group.addTask { try? await api.preroll(itemId) }
            group.addTask {
                try? await Task.sleep(for: .seconds(3))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard let list else {
            ArcLogApp.warn("pre-rolls didn't load in time; playing the film")
            done = true
            return
        }
        guard !list.isEmpty else { done = true; return }
        ArcLogApp.info("playing \(list.count) pre-roll videos before the film")
        clips = list
        engine.onEvent = { event in
            switch event {
            case .ended: next()
            case .failed(let reason):
                ArcLogApp.warn("a pre-roll didn't play: \(reason)")
                next()
            case .ready, .waiting: break
            }
        }
        skipFocused = true
        await play(0)
    }

    /// Plays clip `at` through a cast link (Apple's player can't send the sign-in header), or
    /// moves on when there's no link.
    private func play(_ at: Int) async {
        guard let api = app.api, clips.indices.contains(at) else { finish(); return }
        index = at
        do {
            let url = try await api.castLink(for: clips[at].url)
            guard index == at, !done else { return }
            engine.load(url, headers: [:], startSeconds: 0)
        } catch {
            ArcLogApp.warn("a pre-roll's link failed: \(type(of: error))")
            if index == at { next() }
        }
    }

    private func next() {
        let at = index + 1
        if clips.indices.contains(at) {
            ArcLogApp.debug("moving on from a pre-roll")
            Task { await play(at) }
        } else {
            finish()
        }
    }

    private func finish() {
        guard !done else { return }
        engine.stop()
        done = true
    }
}
