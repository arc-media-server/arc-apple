import Foundation

/// Converted streams start where playback was asked to start, not at the file's beginning: Arc
/// says where in `offset_ms`, and the player's clock counts from there (docs/API.md "Playing").
public enum PlaybackClock {
    /// Where in the file the player is.
    public static func filePosition(_ plan: PlaybackPlan, playerMs: Int64) -> Int64 {
        plan.hls ? plan.offsetMs + playerMs : playerMs
    }

    /// Where the player should start for a point in the file (a remux may begin at an earlier keyframe).
    public static func playerStart(_ plan: PlaybackPlan, fileMs: Int64) -> Int64 {
        plan.hls ? max(0, fileMs - plan.offsetMs) : fileMs
    }

    /// Whether a seek to `fileMs` can stay in the current stream: always for the file as it is;
    /// for a converted stream, only within what's been converted so far (`availableMs` of it).
    /// Anything else asks Arc for a new stream starting there, as the web player does.
    public static func seekInStream(_ plan: PlaybackPlan, fileMs: Int64, availableMs: Int64) -> Bool {
        guard plan.hls else { return true }
        let rel = fileMs - plan.offsetMs
        return rel >= 0 && rel <= availableMs - 2_000
    }
}
