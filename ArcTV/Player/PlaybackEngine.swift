import ArcKit
import AVFoundation
import CoreMedia
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
    /// Plays a little faster or slower (Watch Together catching up with the room); 1 is normal.
    func setRate(_ rate: Float)
    /// Where it is in the stream.
    var currentSeconds: Double { get }
    /// How far into the stream can be reached (for a converted stream, what's converted so far).
    var availableSeconds: Double { get }
    var isPlaying: Bool { get }
    /// Stops and lets the TV go back to its usual picture mode.
    func stop()
    /// What the next stream's picture is, so the TV can switch mode (Match Content) before it
    /// starts. Apple's player reads it from the stream itself and ignores this.
    func prepareDisplay(_ hint: DisplayHint?)
}

extension PlaybackEngine {
    func prepareDisplay(_ hint: DisplayHint?) {}
}

/// A stream's picture as the TV's Match Content needs it: its dynamic range and frame rate.
struct DisplayHint: Equatable {
    enum Range: Equatable { case sdr, hdr10, hlg, dolbyVision }
    var range: Range
    var frameRate: Double?
    var width: Int32 = 3840
    var height: Int32 = 2160

    static let sdr = DisplayHint(range: .sdr, frameRate: nil, width: 1920, height: 1080)

    init(range: Range, frameRate: Double?, width: Int32 = 3840, height: Int32 = 2160) {
        self.range = range
        self.frameRate = frameRate
        self.width = width
        self.height = height
    }

    /// From the file's video track as the server read it.
    init(_ video: MediaStream) {
        let transfer = video.colorTransfer ?? ""
        if video.dolbyVision {
            range = .dolbyVision
        } else if transfer == "smpte2084" {
            range = .hdr10
        } else if transfer == "arib-std-b67" {
            range = .hlg
        } else {
            range = .sdr
        }
        frameRate = video.frameRate
        width = Int32(video.width ?? 3840)
        height = Int32(video.height ?? 2160)
    }

    /// The criteria the TV switches to: a format description with the range's colour tags (Dolby
    /// Vision as dvh1) and the frame rate. Nil when there's nothing to match.
    var criteria: AVDisplayCriteria? {
        let transfer: CFString, primaries: CFString, matrix: CFString
        switch range {
        case .sdr:
            transfer = kCVImageBufferTransferFunction_ITU_R_709_2
            primaries = kCVImageBufferColorPrimaries_ITU_R_709_2
            matrix = kCVImageBufferYCbCrMatrix_ITU_R_709_2
        case .hdr10, .dolbyVision:
            transfer = kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ
            primaries = kCVImageBufferColorPrimaries_ITU_R_2020
            matrix = kCVImageBufferYCbCrMatrix_ITU_R_2020
        case .hlg:
            transfer = kCVImageBufferTransferFunction_ITU_R_2100_HLG
            primaries = kCVImageBufferColorPrimaries_ITU_R_2020
            matrix = kCVImageBufferYCbCrMatrix_ITU_R_2020
        }
        let extensions: [CFString: Any] = [
            kCMFormatDescriptionExtension_TransferFunction: transfer,
            kCMFormatDescriptionExtension_ColorPrimaries: primaries,
            kCMFormatDescriptionExtension_YCbCrMatrix: matrix,
        ]
        var description: CMVideoFormatDescription?
        let codec = range == .dolbyVision ? kCMVideoCodecType_DolbyVisionHEVC : kCMVideoCodecType_HEVC
        CMVideoFormatDescriptionCreate(allocator: nil, codecType: codec, width: width, height: height,
                                       extensions: extensions as CFDictionary, formatDescriptionOut: &description)
        guard let description else { return nil }
        return AVDisplayCriteria(refreshRate: Float(frameRate ?? 0), formatDescription: description)
    }
}

/// Match Content: asks the TV for a picture mode (nil goes back to the usual one).
enum DisplayMode {
    @MainActor
    static func request(_ criteria: AVDisplayCriteria?, near view: UIView) {
        // Windows without a display manager (the simulator's) don't answer avDisplayManager at
        // all, and asking stops the app: check first, and play without Match Content there.
        let selector = NSSelectorFromString("avDisplayManager")
        let window = [view.window, keyWindow].compactMap { $0 }.first { $0.responds(to: selector) }
        guard let manager = window?.avDisplayManager, manager.isDisplayCriteriaMatchingEnabled else { return }
        manager.preferredDisplayCriteria = criteria
    }

    /// Whether the TV is still switching mode (the picture would be lost if it started now).
    @MainActor
    static func switching(near view: UIView) -> Bool {
        let selector = NSSelectorFromString("avDisplayManager")
        let window = [view.window, keyWindow].compactMap { $0 }.first { $0.responds(to: selector) }
        return window?.avDisplayManager.isDisplayModeSwitchInProgress ?? false
    }

    @MainActor
    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
    }
}
