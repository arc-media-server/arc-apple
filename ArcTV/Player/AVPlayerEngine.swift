import AVFoundation
import AVKit
import UIKit

/// Apple's own player (AVPlayer) behind the engine interface, drawing into an AVPlayerLayer.
/// It plays what Arc sends as it is (MP4) or repackaged (fMP4 HLS), with Apple's handling of
/// HDR, Dolby Vision and Dolby Digital Plus (Atmos included).
@MainActor
final class AVPlayerEngine: PlaybackEngine {
    var onEvent: ((EngineEvent) -> Void)?

    private let player = AVPlayer()
    private let surface: PlayerLayerView
    private var observations: [NSKeyValueObservation] = []
    private var endObserver: NSObjectProtocol?
    private var startSeconds: Double = 0
    private var started = false
    private var waiting = false
    private var loadTask: Task<Void, Never>?

    init() {
        surface = PlayerLayerView()
        surface.playerLayer.player = player
        surface.playerLayer.videoGravity = .resizeAspect
        surface.backgroundColor = .black
    }

    var view: UIView { surface }

    func load(_ url: URL, headers: [String: String], startSeconds: Double) {
        reset()
        self.startSeconds = startSeconds
        // Streams from a cast link carry their own token; anything else gets the sign-in header.
        let options: [String: Any] = headers.isEmpty ? [:] : ["AVURLAssetHTTPHeaderFieldsKey": headers]
        let asset = AVURLAsset(url: url, options: options)
        loadTask = Task { [weak self] in
            // Match Content: the TV switches to the title's dynamic range and frame rate before
            // the picture starts, as Apple's own player does. A custom layer has to ask for it.
            let criteria = try? await asset.load(.preferredDisplayCriteria)
            guard let self, !Task.isCancelled else { return }
            self.applyDisplayCriteria(criteria)
            self.attach(AVPlayerItem(asset: asset))
        }
    }

    private func attach(_ item: AVPlayerItem) {
        observations = [
            item.observe(\.status, options: [.new]) { [weak self] item, _ in
                Task { @MainActor in self?.statusChanged(item) }
            },
            player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
                Task { @MainActor in self?.timeControlChanged(player.timeControlStatus) }
            },
        ]
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onEvent?(.ended) }
        }
        player.replaceCurrentItem(with: item)
    }

    private func statusChanged(_ item: AVPlayerItem) {
        switch item.status {
        case .readyToPlay where !started:
            started = true
            // A converted stream is a growing (EVENT) playlist: start where asked, not at its live edge.
            player.seek(to: CMTime(seconds: startSeconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                Task { @MainActor in
                    self?.player.play()
                    self?.onEvent?(.ready)
                }
            }
        case .failed:
            let error = item.error as NSError?
            onEvent?(.failed(reason: error.map { "\($0.domain) \($0.code)" } ?? "unknown"))
        default:
            break
        }
    }

    private func timeControlChanged(_ status: AVPlayer.TimeControlStatus) {
        let now = status == .waitingToPlayAtSpecifiedRate
        guard now != waiting, started else { return }
        waiting = now
        onEvent?(.waiting(now))
    }

    func play() { player.play() }
    func pause() { player.pause() }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    var currentSeconds: Double {
        let t = player.currentTime().seconds
        return t.isFinite ? max(0, t) : 0
    }

    var availableSeconds: Double {
        guard let range = player.currentItem?.seekableTimeRanges.last?.timeRangeValue else { return 0 }
        let end = CMTimeRangeGetEnd(range).seconds
        return end.isFinite ? end : 0
    }

    var isPlaying: Bool { player.timeControlStatus != .paused }

    func stop() {
        reset()
        applyDisplayCriteria(nil)
    }

    private func reset() {
        loadTask?.cancel()
        loadTask = nil
        observations.forEach { $0.invalidate() }
        observations = []
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        started = false
        waiting = false
    }

    private func applyDisplayCriteria(_ criteria: AVDisplayCriteria?) {
        guard let manager = surface.window?.avDisplayManager ?? Self.keyWindow?.avDisplayManager,
              manager.isDisplayCriteriaMatchingEnabled else { return }
        manager.preferredDisplayCriteria = criteria
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
    }
}

/// A view whose layer is the player's picture.
final class PlayerLayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
