import ArcKit
import AVFoundation
import UIKit

/// What each engine plays on this Apple TV, as Arc's playback decision expects it.
enum DeviceCaps {
    /// Apple's player (AVPlayer) opens MP4 (and Arc's fMP4 HLS), decodes H.264 and HEVC, AAC and
    /// MP3, and sends Dolby Digital (Plus, with Atmos) on to the TV or receiver. It can't play
    /// TrueHD or DTS, so Arc converts those to Dolby Digital Plus 5.1. Dolby Vision is asked for as
    /// profile 8 only: Arc tags copied HEVC as hvc1, which shows profile 8's HDR10 base correctly
    /// but would show profile 5 (no base layer) in the wrong colours.
    @MainActor
    static func apple() -> PlayerCaps {
        let hdr = AVPlayer.eligibleForHDRPlayback
        return PlayerCaps(
            containers: ["mp4"],
            video: ["h264", "hevc"],
            audio: ["aac", "mp3", "ac3", "eac3"],
            maxHeight: screenHeight,
            audioPassthrough: [],
            // Unknown rather than SDR only when the TV isn't showing HDR now (an SDR menu mode):
            // Arc then sends HDR as it is and the Apple TV maps it itself.
            hdrFormats: hdr ? ["hdr10", "hlg", "dolby_vision"] : nil,
            dolbyVisionProfiles: hdr ? [8] : nil,
            maxAudioChannels: audioChannels
        )
    }

    /// mpv (the patched build) opens almost anything and decodes it (VideoToolbox for H.264, HEVC
    /// and AV1, FFmpeg for the rest), so Arc sends files as they are. Dolby Vision 5, 7 (converted
    /// to 8.1 on the fly) and 8 reach the TV as Dolby Vision; HDR10+ keeps its metadata. TrueHD,
    /// DTS and the rest are decoded to multichannel PCM; Dolby Digital (Plus) goes to Apple's
    /// decoder, Atmos kept. Arc still converts when the bandwidth needs it.
    @MainActor
    static func mpv() -> PlayerCaps {
        let hdr = AVPlayer.eligibleForHDRPlayback
        return PlayerCaps(
            containers: ["mp4", "mkv", "webm", "mpegts", "avi", "ogg", "flv"],
            video: ["h264", "hevc", "av1", "vp9", "vp8", "mpeg2video", "mpeg4", "vc1"],
            audio: ["aac", "mp3", "ac3", "eac3", "truehd", "dts", "flac", "alac", "opus", "vorbis", "mp2",
                    "pcm_s16le", "pcm_s24le", "pcm_s32le", "pcm_bluray", "pcm_dvd"],
            maxHeight: screenHeight,
            audioPassthrough: [],
            hdrFormats: hdr ? ["hdr10", "hdr10_plus", "hlg", "dolby_vision"] : nil,
            dolbyVisionProfiles: hdr ? [5, 7, 8] : nil,
            // 10-bit H.264 (Hi10P) decodes in software; HEVC and AV1 10-bit in hardware.
            maxBitDepth: 10,
            maxAudioChannels: audioChannels
        )
    }

    /// The most channels the sound output takes now (the TV or receiver over HDMI: 2, 6 or 8),
    /// so Arc mixes down only what it can't play; nil when tvOS doesn't say, which leaves the
    /// sound as it is. Read for each new player, so a receiver switched on later counts.
    @MainActor
    private static var audioChannels: Int? {
        let n = AVAudioSession.sharedInstance().maximumOutputNumberOfChannels
        let channels: Int? = (1...32).contains(n) ? n : nil
        ArcLogApp.debug("sound output channels: \(channels.map(String.init) ?? "unknown")")
        return channels
    }

    /// This Apple TV as Playback Info shows it: "2160p · HDR · 5.1" (the picture and sound
    /// it's sending to the TV now).
    @MainActor
    static var summary: String {
        let channels = AVAudioSession.sharedInstance().maximumOutputNumberOfChannels
        return ["\(screenHeight)p", AVPlayer.eligibleForHDRPlayback ? "HDR" : "SDR",
                channels > 0 ? StatsFormat.channelLayout(channels) : nil].compactMap { $0 }.joined(separator: " · ")
    }

    @MainActor
    private static var screenHeight: Int {
        let bounds = UIScreen.main.nativeBounds
        let height = Int(min(bounds.width, bounds.height))
        return height >= 1080 ? height : 1080
    }
}

/// Which engine the player uses: mpv, unless this Apple TV was set to Apple's player (the
/// `player.engine` default, "apple"; for comparing the two and for diagnosing a file).
enum EngineChoice {
    static let key = "player.engine"

    static var prefersApple: Bool { UserDefaults.standard.string(forKey: key) == "apple" }

    @MainActor
    static func make() -> PlaybackEngine { prefersApple ? AVPlayerEngine() : MPVEngine() }
}
