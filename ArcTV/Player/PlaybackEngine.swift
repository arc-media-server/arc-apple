import UIKit

/// What the engine reports as it plays.
enum EngineEvent {
    /// The stream is loaded and playing from where it was asked to start.
    case ready
    /// It can't be played here; `reason` is for the log (no URLs).
    case failed(reason: String)
    /// Waiting for more of the stream (the spinner), or no longer waiting.
    case waiting(Bool)
    case ended
}

/// The player behind Arc's own controls. The screens only talk to this, so a different engine
/// (AetherEngine, say, for lossless audio or Dolby Vision profile 7) can replace Apple's player
/// without touching them (decision on arc-media-server#80).
@MainActor
protocol PlaybackEngine: AnyObject {
    var onEvent: ((EngineEvent) -> Void)? { get set }
    /// The picture, for the player screen to show.
    var view: UIView { get }
    /// Loads a stream and starts it `startSeconds` into the stream.
    func load(_ url: URL, headers: [String: String], startSeconds: Double)
    func play()
    func pause()
    func seek(to seconds: Double)
    /// Where it is in the stream.
    var currentSeconds: Double { get }
    /// How far into the stream can be reached (for a converted stream, what's converted so far).
    var availableSeconds: Double { get }
    var isPlaying: Bool { get }
    /// Stops and lets the TV go back to its usual picture mode.
    func stop()
}
