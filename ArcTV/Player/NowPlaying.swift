import ArcKit
import MediaPlayer
import UIKit

/// What's playing, told to tvOS (Control Center, the Now Playing screen, Siri) with its picture
/// and position, and the system's play, pause, skip and seek commands sent to the player: the
/// way a custom engine joins the system's media controls (Apple's own player does this itself).
@MainActor
final class NowPlaying {
    struct Actions {
        var toggle: () -> Void
        var play: () -> Void
        var pause: () -> Void
        var skip: (Int64) -> Void
        var seek: (Int64) -> Void
    }

    private var targets: [(MPRemoteCommand, Any)] = []
    private var info: [String: Any] = [:]
    private var artworkTask: Task<Void, Never>?

    func start(_ item: Item, durationMs: Int64, api: ArcAPI, actions: Actions) {
        stop()
        let center = MPRemoteCommandCenter.shared()
        func on(_ command: MPRemoteCommand, _ run: @escaping @MainActor (MPRemoteCommandEvent) -> Bool) {
            let target = command.addTarget { event in
                MainActor.assumeIsolated { run(event) } ? .success : .commandFailed
            }
            command.isEnabled = true
            targets.append((command, target))
        }
        on(center.togglePlayPauseCommand) { _ in actions.toggle(); return true }
        on(center.playCommand) { _ in actions.play(); return true }
        on(center.pauseCommand) { _ in actions.pause(); return true }
        center.skipForwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.preferredIntervals = [10]
        on(center.skipForwardCommand) { _ in actions.skip(10_000); return true }
        on(center.skipBackwardCommand) { _ in actions.skip(-10_000); return true }
        on(center.changePlaybackPositionCommand) { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return false }
            actions.seek(Int64(event.positionTime * 1000))
            return true
        }

        info = [
            MPMediaItemPropertyTitle: item.title,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
            MPMediaItemPropertyPlaybackDuration: Double(durationMs) / 1000,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0,
            MPNowPlayingInfoPropertyPlaybackRate: 0.0,
        ]
        if item.isEpisode {
            if let show = item.seriesTitle { info[MPMediaItemPropertyArtist] = show }
            info[MPMediaItemPropertyAlbumTitle] = L("card.episode_code", item.seasonNumber ?? 0, item.episodeNumber ?? 0)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        // The card's wide picture (an episode's still, a film's backdrop), loaded with the sign-in.
        let card = MediaCard(item: item)
        guard let path = card.thumb ?? card.backdrop, let url = api.absolute(path) else { return }
        let headers = api.authorization
        artworkTask = Task { [weak self] in
            guard let image = await ArtworkLoader.shared.image(url, headers: headers), let self, !Task.isCancelled else { return }
            self.info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = self.info
        }
    }

    /// Where it is and whether it's playing; tvOS runs the clock on from here.
    func update(positionMs: Int64, durationMs: Int64, playing: Bool) {
        guard !info.isEmpty else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(positionMs) / 1000
        info[MPMediaItemPropertyPlaybackDuration] = Double(durationMs) / 1000
        info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func stop() {
        artworkTask?.cancel()
        artworkTask = nil
        for (command, target) in targets { command.removeTarget(target) }
        targets = []
        info = [:]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
