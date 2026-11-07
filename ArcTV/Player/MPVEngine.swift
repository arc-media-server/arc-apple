import AVFoundation
import Libmpv
import UIKit

/// mpv behind the engine interface, for files Apple's player can't take as they are (MKV, TrueHD,
/// DTS, ASS and PGS subtitles, Dolby Vision profile 7). It uses the patched mpv build at
/// github.com/edde746/mpv-build (GPL-3.0, decision on arc-media-server#80). Its `avfoundation`
/// video output hands VideoToolbox frames to an AVSampleBufferDisplayLayer, so HDR and Dolby
/// Vision reach the TV as they are. Audio goes out as multichannel PCM, or for Dolby Digital (Plus)
/// to Apple's own decoder (Atmos kept).
///
/// The default engine (EngineChoice); Apple's player takes over if mpv can't play a file. Before
/// the picture starts it asks the TV for the stream's mode (Match Content: dynamic range and frame
/// rate, from the file as the server read it) and waits for the switch.
@MainActor
final class MPVEngine: PlaybackEngine {
    var onEvent: ((EngineEvent) -> Void)?

    private let surface = SampleBufferView()
    private var mpv: OpaquePointer?
    private var started = false
    private var waiting = false
    private var ended = false
    private var paused = true
    private var rate: Float = 1
    private(set) var currentSeconds: Double = 0
    private(set) var availableSeconds: Double = 0
    private var hint: DisplayHint?
    private var modeTask: Task<Void, Never>?

    func prepareDisplay(_ hint: DisplayHint?) { self.hint = hint }

    init() { surface.backgroundColor = .black }

    var view: UIView { surface }
    var isPlaying: Bool { !paused }

    func load(_ url: URL, headers: [String: String], startSeconds: Double) {
        stopCore()
        guard let handle = mpv_create() else {
            onEvent?(.failed(reason: "mpv could not start"))
            return
        }
        mpv = handle
        set("terminal", "no")
        // The patched video output: VideoToolbox frames into this view's display layer, which
        // mpv takes by its address.
        set("vo", "avfoundation")
        set("hwdec", "videotoolbox")
        var layer = Int64(Int(bitPattern: Unmanaged.passUnretained(surface.displayLayer).toOpaque()))
        mpv_set_option(handle, "wid", MPV_FORMAT_INT64, &layer)
        // Dolby Digital (Plus) to Apple's decoder, so Atmos survives; the rest is decoded to PCM.
        set("audio-spdif", "ac3,eac3")
        set("keep-open", "yes")
        // Loaded paused: it plays once the TV has switched to the stream's mode.
        set("pause", "yes")
        set("cache", "yes")
        set("demuxer-max-bytes", "150MiB")
        set("start", String(format: "%.3f", max(0, startSeconds)))
        // The sign-in header for Arc (a cast link carries its own token and passes none).
        if !headers.isEmpty {
            set("http-header-fields", headers.map { "\($0.key): \($0.value)" }.joined(separator: ","))
        }
        guard mpv_initialize(handle) >= 0 else {
            onEvent?(.failed(reason: "mpv could not initialise"))
            stopCore()
            return
        }
        mpv_observe_property(handle, 0, "time-pos", MPV_FORMAT_DOUBLE)
        mpv_observe_property(handle, 0, "demuxer-cache-time", MPV_FORMAT_DOUBLE)
        mpv_observe_property(handle, 0, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(handle, 0, "paused-for-cache", MPV_FORMAT_FLAG)
        mpv_observe_property(handle, 0, "eof-reached", MPV_FORMAT_FLAG)
        // mpv calls this from its own thread when events are waiting; they're read on the main actor.
        mpv_set_wakeup_callback(handle, { context in
            guard let context else { return }
            let box = Unmanaged<WakeBox>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { box.wake() } }
        }, Unmanaged.passUnretained(wakeBox).toOpaque())
        wakeBox.engine = self
        command(["loadfile", url.absoluteString])
    }

    func play() {
        setFlag("pause", false)
        if rate != 1 { set("speed", String(rate), runtime: true) }
    }

    func pause() { setFlag("pause", true) }

    func setRate(_ rate: Float) {
        guard rate != self.rate else { return }
        self.rate = rate
        set("speed", String(rate), runtime: true)
    }

    /// The display layer scales the frames mpv hands it (the avfoundation output passes them on
    /// whole), so zooming is the layer's: fill the screen, or fit the whole picture.
    func setZoom(_ on: Bool) {
        surface.displayLayer.videoGravity = on ? .resizeAspectFill : .resizeAspect
    }

    func seek(to seconds: Double) {
        command(["seek", String(format: "%.3f", max(0, seconds)), "absolute+exact"])
    }

    func stop() {
        stopCore()
        DisplayMode.request(nil, near: surface)
    }

    /// Asks the TV for the stream's mode, waits while it switches (up to 6 s), then plays.
    private func startAfterModeSwitch() {
        let criteria = hint?.criteria
        if let criteria { DisplayMode.request(criteria, near: surface) }
        modeTask = Task { [weak self] in
            if criteria != nil {
                // The switch starts a moment after the request; then wait for it to finish.
                try? await Task.sleep(for: .milliseconds(300))
                var waited = 0
                while let self, DisplayMode.switching(near: self.surface), waited < 6000, !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                    waited += 100
                }
            }
            guard let self, !Task.isCancelled, self.mpv != nil else { return }
            self.play()
            self.onEvent?(.ready)
        }
    }

    // MARK: mpv

    private let wakeBox = WakeBox()

    private func stopCore() {
        modeTask?.cancel()
        modeTask = nil
        wakeBox.engine = nil
        if let handle = mpv {
            mpv_set_wakeup_callback(handle, nil, nil)
            mpv = nil
            mpv_terminate_destroy(handle)
        }
        started = false
        waiting = false
        ended = false
        paused = true
        currentSeconds = 0
        availableSeconds = 0
        surface.displayLayer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
    }

    /// Reads every waiting event.
    fileprivate func drain() {
        while let handle = mpv, let event = mpv_wait_event(handle, 0)?.pointee, event.event_id != MPV_EVENT_NONE {
            switch event.event_id {
            case MPV_EVENT_FILE_LOADED where !started:
                started = true
                startAfterModeSwitch()
            case MPV_EVENT_END_FILE:
                if let end = event.data?.assumingMemoryBound(to: mpv_event_end_file.self).pointee,
                   end.reason == MPV_END_FILE_REASON_ERROR {
                    onEvent?(.failed(reason: String(cString: mpv_error_string(end.error))))
                }
            case MPV_EVENT_PROPERTY_CHANGE:
                if let property = event.data?.assumingMemoryBound(to: mpv_event_property.self).pointee {
                    changed(property)
                }
            case MPV_EVENT_SHUTDOWN:
                return
            default:
                break
            }
        }
    }

    private func changed(_ property: mpv_event_property) {
        let name = String(cString: property.name)
        switch property.format {
        case MPV_FORMAT_DOUBLE:
            guard let value = property.data?.assumingMemoryBound(to: Double.self).pointee, value.isFinite else { return }
            if name == "time-pos" { currentSeconds = max(0, value) }
            if name == "demuxer-cache-time" { availableSeconds = value }
        case MPV_FORMAT_FLAG:
            guard let value = property.data?.assumingMemoryBound(to: Int32.self).pointee else { return }
            let on = value != 0
            switch name {
            case "pause":
                paused = on
            case "paused-for-cache" where started && on != waiting:
                waiting = on
                onEvent?(.waiting(on))
            case "eof-reached" where on && !ended:
                ended = true
                onEvent?(.ended)
            default:
                break
            }
        default:
            break
        }
    }

    private func set(_ name: String, _ value: String, runtime: Bool = false) {
        guard let mpv else { return }
        if runtime {
            mpv_set_property_string(mpv, name, value)
        } else {
            mpv_set_option_string(mpv, name, value)
        }
    }

    private func setFlag(_ name: String, _ on: Bool) {
        guard let mpv else { return }
        var value: Int32 = on ? 1 : 0
        mpv_set_property(mpv, name, MPV_FORMAT_FLAG, &value)
    }

    private func command(_ args: [String]) {
        guard let mpv else { return }
        var strings: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) } + [nil]
        defer { strings.forEach { free($0) } }
        strings.withUnsafeMutableBufferPointer { buffer in
            buffer.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buffer.count) {
                _ = mpv_command(mpv, $0)
            }
        }
    }
}

/// What mpv's wakeup callback holds: it outlives a stopped core, so a late wakeup finds nothing.
private final class WakeBox: @unchecked Sendable {
    @MainActor weak var engine: MPVEngine?
    @MainActor func wake() { engine?.drain() }
}

/// A view whose layer is the display layer mpv draws into.
final class SampleBufferView: UIView {
    override static var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }
    var displayLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }
}
