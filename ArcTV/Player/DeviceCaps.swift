import ArcKit
import AVFoundation
import UIKit

/// What Apple's player plays on this Apple TV, as Arc's playback decision expects it.
///
/// AVPlayer opens MP4 (and Arc's fMP4 HLS), decodes H.264 and HEVC, AAC and MP3, and sends
/// Dolby Digital (Plus, with Atmos) on to the TV or receiver. It can't play TrueHD or DTS, so Arc
/// converts those to Dolby Digital Plus 5.1. Dolby Vision is asked for as profile 8 only: Arc
/// tags copied HEVC as hvc1, which shows profile 8's HDR10 base correctly but would show
/// profile 5 (no base layer) in the wrong colours.
enum DeviceCaps {
    @MainActor
    static func current() -> PlayerCaps {
        let hdr = AVPlayer.eligibleForHDRPlayback
        let bounds = UIScreen.main.nativeBounds
        let height = Int(min(bounds.width, bounds.height))
        return PlayerCaps(
            containers: ["mp4"],
            video: ["h264", "hevc"],
            audio: ["aac", "mp3", "ac3", "eac3"],
            maxHeight: height >= 1080 ? height : 1080,
            audioPassthrough: [],
            // Unknown rather than SDR only when the TV isn't showing HDR now (an SDR menu mode):
            // Arc then sends HDR as it is and the Apple TV maps it itself.
            hdrFormats: hdr ? ["hdr10", "hlg", "dolby_vision"] : nil,
            dolbyVisionProfiles: hdr ? [8] : nil
        )
    }
}
