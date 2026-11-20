import ArcKit
import AVFoundation

/// A title's theme tune, quietly under its page, as the web's ThemeMusic.tsx and Plex: played
/// once, fading in to a quarter of the volume, and fading out when stopped. Audio only, so it
/// sits beside the playback engines rather than behind PlaybackEngine.
@MainActor
final class ThemeMusic {
    static let volume: Float = 0.25
    private var player: AVPlayer?
    private var fade: Task<Void, Never>?
    private var failure: NSObjectProtocol?

    func play(_ url: URL, headers: [String: String]) {
        clear()
        let asset = AVURLAsset(url: url, options: headers.isEmpty ? [:] : ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.volume = 0
        self.player = player
        // A tune that won't play is passed over; the page carries on.
        failure = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { @Sendable _ in
            ArcLogApp.debug("theme music didn't play")
        }
        player.play()
        ramp(player, to: Self.volume, seconds: 0.75)
    }

    /// Fades the tune out and lets it go.
    func stop() {
        guard let player else { return }
        self.player = nil
        ramp(player, to: 0, seconds: 0.5) { player.pause() }
        removeObserver()
    }

    private func clear() {
        fade?.cancel()
        player?.pause()
        player = nil
        removeObserver()
    }

    private func removeObserver() {
        if let failure { NotificationCenter.default.removeObserver(failure) }
        failure = nil
    }

    private func ramp(_ player: AVPlayer, to target: Float, seconds: Double, then done: (() -> Void)? = nil) {
        fade?.cancel()
        let start = player.volume, steps = 15
        fade = Task { @MainActor in
            for step in 1...steps {
                try? await Task.sleep(for: .seconds(seconds / Double(steps)))
                if Task.isCancelled { break }
                player.volume = start + (target - start) * Float(step) / Float(steps)
            }
            done?()
        }
    }
}
