import ArcKit
import Foundation

/// What the player is asked to play, and from where in the file.
struct PlayRequest: Identifiable, Hashable {
    let item: Item
    let startMs: Int64
    /// Played in a Watch Together room: the room decides where and whether it plays.
    var together = false
    /// The player moving on by itself (Up Next, the queue): no pre-rolls.
    var playingOn = false
    /// The play queue's entry this is (Home's Queue row, Shuffle, the queue moving on).
    var queueEntry: String?
    var fileId: Int64?
    var id: String {
        item.id + "@\(startMs)" + (together ? "|together" : "") + (playingOn ? "|on" : "") + (fileId.map { "|file=\($0)" } ?? "")
    }

    /// A film started from the beginning plays the pre-roll videos first, as on the web: not when
    /// resuming, in Watch Together, or when the player moves on.
    var wantsPreroll: Bool { item.kind == "movie" && startMs == 0 && !together && !playingOn }
}
