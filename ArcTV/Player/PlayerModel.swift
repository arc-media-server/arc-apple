import ArcKit
import Foundation
import Observation

/// Plays a movie or episode the way Arc's web player does: ask Arc how to play it with what this
/// Apple TV plays, play the file or the converted stream, save progress every 10 seconds and on
/// pause and close, keep a converting session alive, and end it when done.
@MainActor
@Observable
final class PlayerModel {
    let item: Item
    private(set) var loading = true
    private(set) var waiting = false
    private(set) var problem: String?
    private(set) var positionMs: Int64 = 0
    private(set) var playing = false
    private(set) var ended = false
    var durationMs: Int64 { plan.map { $0.durationMs > 0 ? $0.durationMs : item.durationMs } ?? item.durationMs }

    /// The subtitles on screen (nil: off), and their lines when they're text.
    private(set) var subtitle: SubtitleTrack?
    private var cues: [SubtitleCue] = []
    /// The episode that follows, for Up Next (found when an episode starts).
    private var episodeNext: Item?
    /// The play queue's next title to play, and its entry: it comes before the next episode, and
    /// plays on whatever Auto-Play is set to, since it was queued on purpose.
    private(set) var queued: (item: Item, entry: String)?
    /// What Up Next and the end of the title move on to.
    var next: Item? { queued?.item ?? episodeNext }
    var nextIsQueued: Bool { queued != nil }

    func setQueued(_ item: Item?, entry: String?) {
        if let item, let entry { queued = (item, entry) } else { queued = nil }
    }
    /// The profile's playback preferences (Auto-Play, auto-skip, subtitles).
    private(set) var prefs: Prefs?
    var subtitleTracks: [SubtitleTrack] { plan?.subtitleTracks ?? [] }
    var audioTracks: [AudioTrack] { plan?.audioTracks ?? [] }
    var audioStream: Int { plan?.audioStream ?? -1 }
    /// The line of subtitles showing now.
    var caption: String? {
        cues.isEmpty ? nil : cue(at: SubtitleTiming.cueTimeMs(positionMs, offsetMs: subtitleOffsetMs), in: cues)?.text
    }
    /// Subtitle timing, per file and track, for this playback only (as the web's and Android's).
    private var subtitleOffsets: [String: Int64] = [:]
    /// Only text subtitles, which the app draws, can be moved; pictures are part of the video.
    var subtitleTimingAdjustable: Bool { subtitle.map { !$0.image } ?? false }
    var subtitleOffsetMs: Int64 {
        guard subtitleTimingAdjustable, let track = subtitle else { return 0 }
        return subtitleOffsets[SubtitleTiming.key(fileId: fileId, trackId: track.id)] ?? 0
    }
    /// Show the subtitles half a second earlier or later, or Reset (nil).
    func shiftSubtitles(_ deltaMs: Int64?) {
        guard subtitleTimingAdjustable, let track = subtitle else { return }
        let key = SubtitleTiming.key(fileId: fileId, trackId: track.id)
        subtitleOffsets[key] = SubtitleTiming.shifted(subtitleOffsets[key] ?? 0, deltaMs)
        log.debug("subtitle timing now \(subtitleOffsets[key] ?? 0) ms")
    }
    /// The intro, recap or credits playing now (for Skip).
    var marker: Marker? { plan.flatMap { activeMarker($0.markers, at: positionMs) } }
    /// Whether the Up Next card is due.
    var upNextDue: Bool { next != nil && !loading && showsUpNext(markers: plan?.markers ?? [], positionMs: positionMs, durationMs: durationMs) }

    /// The title's files (editions, versions) and the one playing.
    var versions: [Version] { plan?.versions ?? [] }
    var fileId: Int64 { plan?.fileId ?? 0 }
    var chapters: [Chapter] { plan?.chapters ?? [] }
    /// How the stream arrives, for the Info card: as it is, repackaged, or converted.
    var methodName: String? {
        switch plan?.method {
        case "direct": return L("player.method_direct")
        case "remux": return L("player.method_remux")
        case "transcode": return L("player.method_transcode")
        default: return nil
        }
    }
    /// Which engine plays it (mpv or Apple's player), for the Info card.
    var engineName: String { engine is MPVEngine ? L("player.engine_mpv") : L("player.engine_apple") }
    /// The quality limit chosen (nil: the original), and the limits worth offering for this file.
    private(set) var maxKbps: Int?
    /// The controls' Cast and Episodes cards: the title's cast (an episode's, else its show's),
    /// and the episodes of its season.
    private(set) var cast: [Credit] = []
    private(set) var seasonEpisodes: [Item] = []
    /// The episode is outside the show's order ("Not in This Order"): the Episodes card lists the
    /// others like it, without "S1 · E8" codes, and there's no Previous Episode.
    private(set) var outsideOrder = false
    /// The episode before this one in its season, for the Info card's Previous button.
    var previous: Item? {
        guard !outsideOrder, let i = seasonEpisodes.firstIndex(where: { $0.id == item.id }), i > 0 else { return nil }
        return seasonEpisodes[i - 1]
    }
    /// Playback Speed and Zoom Mode (the Playback menu), kept when the stream or engine changes.
    private(set) var speed: Float = 1
    private(set) var zoomed = false
    /// Playback Info ("stats for nerds") is showing, from the Playback menu.
    var showsInfo = false
    var qualities: [Int] {
        let offered = offeredQualities(sourceKbps: plan?.sourceKbps ?? 0)
        guard let limit = plan?.serverLimitKbps, limit > 0 else { return offered }
        return offered.filter { $0 <= limit }
    }
    /// The file's timeline thumbnails, once Arc has made them.
    private(set) var trickplay: Trickplay?
    /// When the viewer last moved through the timeline (the thumbnail shows for a moment after).
    private(set) var seekedAt: Date?

    /// mpv by default; Apple's player when this Apple TV is set to it, or after mpv couldn't play
    /// a file (the screen shows whichever is current).
    private(set) var engine: PlaybackEngine
    private let api: ArcAPI
    /// The version the viewer chose (nil: Arc's choice).
    private var fileChoice: Int64?
    private var plan: PlaybackPlan?
    private var caps: PlayerCaps
    private var retried = false
    /// The viewer's audio track and picture subtitles to draw in (asked of Arc on every load).
    private var audioChoice: Int?
    private var burn: String?
    /// Subtitles were chosen (by the profile's preferences or the viewer): don't choose again.
    private var subtitlesSettled = false
    private var skipped: Set<Int64> = []
    private var loops: [Task<Void, Never>] = []
    private var startTask: Task<Void, Never>?
    private var lastReport = Date.distantPast
    private let log = ArcLog.shared
    private let onRefused: () -> Void

    init(api: ArcAPI, item: Item, startMs: Int64, engine: PlaybackEngine, onRefused: @escaping () -> Void) {
        self.api = api
        self.item = item
        self.engine = engine
        self.onRefused = onRefused
        caps = Self.caps(for: engine)
        positionMs = startMs
        engine.onEvent = { [weak self] in self?.handle($0) }
    }

    func start() {
        load(at: positionMs)
        Task { [weak self] in await self?.loadExtras() }
        loops = [
            Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    self?.tick()
                }
            },
            Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    await self?.keepAlive()
                }
            },
        ]
    }

    /// Asks Arc for a stream starting at `fileMs` and plays it. Ends the converting session it replaces.
    private func load(at fileMs: Int64) {
        startTask?.cancel()
        let old = plan?.sessionId
        loading = true
        problem = nil
        startTask = Task {
            if let old { await api.stopTranscode(old) }
            do {
                let p = try await api.startPlayback(itemId: item.id, request: PlaybackRequest(caps: caps, startMs: fileMs, fileId: fileChoice ?? plan.flatMap { $0.fileId > 0 ? $0.fileId : nil },
                                                                                               audioStream: audioChoice, burnSubtitle: burn, maxKbps: maxKbps))
                guard !Task.isCancelled else { return }
                let fileChanged = plan?.fileId != p.fileId
                plan = p
                settleSubtitles()
                if fileChanged { loadTrickplay(p) }
                log.info("playing by \(p.method)" + (p.reasons.isEmpty ? "" : " (\(p.reasons.joined(separator: ", ")))"))
                // Apple's player fetches a converted stream's pieces itself, without the app's
                // header: a cast link carries its own token. An older Arc without them gets the header.
                var headers: [String: String] = [:]
                let url: URL
                if let link = try? await api.castLink(for: p.url) {
                    url = link
                } else if let direct = api.absolute(p.url) {
                    url = direct
                    headers = api.authorization
                } else {
                    throw UnexpectedAnswer()
                }
                guard !Task.isCancelled else { return }
                engine.prepareDisplay(displayHint(for: p))
                engine.load(url, headers: headers, startSeconds: Double(PlaybackClock.playerStart(p, fileMs: fileMs)) / 1000)
            } catch is CancellationError {
            } catch let error as APIError where error.status == 401 {
                onRefused()
            } catch let error as APIError {
                log.warn("playback refused: \(error.status)")
                fail(error.message)
            } catch {
                log.warn("playback failed to start: \(type(of: error))")
                fail(L("player.failed"))
            }
        }
    }

    /// The profile's preferences and the next episode, alongside starting the stream.
    private func loadExtras() async {
        do {
            prefs = try await api.prefs()
            settleSubtitles()
        } catch {
            log.debug("preferences unavailable in the player: \(type(of: error))")
        }
        if item.isEpisode {
            do { episodeNext = try await api.nextEpisode(item.id) } catch { log.debug("next episode unavailable: \(type(of: error))") }
        }
        await loadCastAndEpisodes()
    }

    private func loadCastAndEpisodes() async {
        func actors(_ credits: [Credit]) -> [Credit] { credits.filter { $0.role == "actor" || $0.role.isEmpty } }
        do {
            cast = actors(try await api.item(item.id).credits)
            if cast.isEmpty, item.isEpisode, let show = item.parentId {
                cast = actors(try await api.item(show).credits)
            }
        } catch {
            log.debug("cast unavailable in the player: \(type(of: error))")
        }
        guard item.isEpisode, let show = item.parentId else { return }
        do {
            // The episode's season, or the episodes outside the order when it's one of them.
            let tab = try await api.seasons(seriesId: show).tab(containing: item.id)
            seasonEpisodes = tab?.episodes ?? []
            outsideOrder = tab?.isUnplaced == true
            if outsideOrder { log.debug("the episode is outside the show's order") }
        } catch {
            log.debug("episodes unavailable in the player: \(type(of: error))")
        }
    }

    /// Playback Speed: the viewer's own choice (Watch Together sets the rate itself instead).
    func chooseSpeed(_ speed: Float) {
        self.speed = speed
        engine.setRate(speed)
    }

    /// Zoom Mode: the whole picture (Normal), or the screen filled and the edges cut (Zoom).
    func chooseZoom(_ on: Bool) {
        zoomed = on
        engine.setZoom(on)
    }

    /// Back to the start (the Info card's Restart).
    func restart() { seek(toMs: 0) }

    /// Turns on the subtitles the profile's preferences ask for, once both are known.
    private func settleSubtitles() {
        guard !subtitlesSettled, let prefs, let plan else { return }
        subtitlesSettled = true
        let audioLanguage = plan.audioTracks.first { $0.index == plan.audioStream }?.language
        guard let pick = ArcKit.chooseSubtitle(plan.subtitleTracks, preferred: prefs.subtitleLanguage, audioLanguage: audioLanguage, mode: prefs.subtitleMode) else { return }
        log.debug("subtitles on by the profile's preferences (\(pick.image ? "picture" : "text"))")
        show(pick)
    }

    /// The viewer chose subtitles (nil: Off). Remembered in the profile, as the web player does.
    func chooseSubtitle(_ track: SubtitleTrack?) {
        subtitlesSettled = true
        show(track)
        if let remembered = rememberedSubtitleLanguage(track, mode: prefs?.subtitleMode ?? "") {
            savePref("subtitle_language", remembered)
        }
    }

    private func show(_ track: SubtitleTrack?) {
        subtitle = track
        cues = []
        if let track, track.image {
            // Picture subtitles can only be drawn in by Arc, which converts the video to do it.
            guard burn != track.id else { return }
            burn = track.id
            load(at: positionMs)
            return
        }
        if burn != nil {
            burn = nil
            load(at: positionMs)
        }
        guard let track, let fileId = plan?.fileId else { return }
        let api = self.api, id = item.id
        Task { [weak self] in
            do {
                let lines = try await api.subtitleCues(itemId: id, track: track.id, fileId: fileId)
                guard let self, self.subtitle?.id == track.id else { return }
                self.cues = lines
                self.log.debug("subtitles loaded: \(lines.count) lines")
            } catch {
                ArcLog.shared.warn("subtitles failed to load: \(type(of: error))")
            }
        }
    }

    /// The viewer chose another version (edition or copy) of the title: it plays from the same place.
    func chooseVersion(_ id: Int64) {
        guard id != fileId else { return }
        fileChoice = id
        audioChoice = nil
        burn = nil
        log.info("version changed")
        load(at: positionMs)
    }

    /// The viewer chose a quality limit (nil: the original). Arc converts down to it.
    func chooseQuality(_ kbps: Int?) {
        guard kbps != maxKbps else { return }
        maxKbps = kbps
        log.info(kbps == nil ? "quality: original" : "quality limited to \(kbps!) kbps")
        load(at: positionMs)
    }

    /// Jumps to a chapter's start.
    func jump(to chapter: Chapter) {
        seek(by: chapter.startMs - positionMs)
    }

    /// The chapter playing now.
    var chapter: Chapter? { chapters.last { $0.startMs <= positionMs } }

    /// Timeline thumbnails for the file now playing; none is fine (they're made in the background).
    private func loadTrickplay(_ p: PlaybackPlan) {
        trickplay = nil
        guard p.fileId > 0 else { return }
        let api = self.api, id = item.id, file = p.fileId
        Task { [weak self] in
            do {
                let found = try await api.trickplay(itemId: id, fileId: file)
                guard let self, self.plan?.fileId == file else { return }
                self.trickplay = found
                self.log.debug(found == nil ? "no timeline thumbnails yet" : "timeline thumbnails: \(found!.info.count)")
            } catch {
                ArcLog.shared.debug("timeline thumbnails unavailable: \(type(of: error))")
            }
        }
    }

    /// The viewer chose an audio track: Arc may need to repackage or convert for it.
    func chooseAudio(_ index: Int) {
        guard index != audioStream else { return }
        audioChoice = index
        log.info("audio track changed")
        load(at: positionMs)
        if let language = audioTracks.first(where: { $0.index == index })?.language { savePref("audio_language", language) }
    }

    /// Jumps to the end of the intro, recap or credits.
    func skipMarker() {
        guard let m = marker else { return }
        skipped.insert(m.startMs)
        seek(by: m.endMs - positionMs)
    }

    private func savePref(_ key: String, _ value: String) {
        let api = self.api
        Task {
            do { try await api.updatePrefs([key: .string(value)]) } catch { ArcLog.shared.warn("saving the preference \(key) failed: \(type(of: error))") }
        }
    }

    private func handle(_ event: EngineEvent) {
        switch event {
        case .ready:
            loading = false
            playing = true
        case .waiting(let now):
            waiting = now
            if now { log.debug("waiting for the stream") }
        case .ended:
            ended = true
            playing = false
            report("stopped", position: durationMs)
        case .failed(let reason):
            onStreamError(reason)
        }
    }

    /// The file as it is (or repackaged) didn't play here: ask Arc to do more, once, as the web player does.
    private func onStreamError(_ reason: String) {
        guard let p = plan else { return }
        log.warn("the stream didn't play (\(p.method), \(reason))")
        // mpv couldn't play it: the same position with Apple's player (and what it plays), once.
        if engine is MPVEngine {
            log.warn("mpv couldn't play this file; Apple's player instead")
            switchToApple()
            load(at: positionMs)
            return
        }
        if !retried && p.method != "transcode" {
            retried = true
            caps = caps.fallback(after: p.method)
            load(at: positionMs)
        } else {
            fail(L("player.failed"))
        }
    }

    private func fail(_ message: String) {
        loading = false
        problem = message
    }

    private func tick() {
        guard let p = plan, !loading else { return }
        positionMs = PlaybackClock.filePosition(p, playerMs: Int64(engine.currentSeconds * 1000))
        playing = engine.isPlaying
        if playing && Date().timeIntervalSince(lastReport) >= 10 { report("playing") }
        // Skip Intros Automatically: intros and recaps, each once (not credits, which carry Up Next).
        if prefs?.autoSkip == true, let m = marker, m.kind != "credits", !skipped.contains(m.startMs), playing {
            log.debug("skipping the \(m.kind) automatically")
            skipMarker()
        }
    }

    func togglePlay() {
        guard !loading else { return }
        if engine.isPlaying {
            engine.pause()
            playing = false
            report("paused")
        } else {
            engine.play()
            playing = true
        }
    }

    /// Plays or pauses as the Watch Together room says (not the viewer's own toggle).
    func setPlaying(_ on: Bool) {
        guard !loading, on != engine.isPlaying else { return }
        if on { engine.play() } else { engine.pause() }
        playing = on
    }

    /// Plays at `rate` while catching up with the room (1 is normal).
    func setRate(_ rate: Float) { engine.setRate(rate) }

    /// Moves to `ms` in the file (the room's position).
    func seek(toMs ms: Int64) { seek(by: ms - positionMs) }

    /// Loading or buffering, for the room's ready check.
    var busy: Bool { loading || waiting }

    /// Moves by `deltaMs` in the file: within the stream when it can, else a new stream from there.
    func seek(by deltaMs: Int64) {
        guard let p = plan, !loading else { return }
        seekedAt = Date()
        let target = min(max(0, positionMs + deltaMs), max(0, durationMs - 1_000))
        positionMs = target
        if PlaybackClock.seekInStream(p, fileMs: target, availableMs: Int64(engine.availableSeconds * 1000)) {
            engine.seek(to: Double(PlaybackClock.playerStart(p, fileMs: target)) / 1000)
        } else {
            log.debug("seeking past what's converted: a new stream")
            load(at: target)
        }
    }

    func retry() {
        retried = false
        caps = Self.caps(for: engine)
        load(at: positionMs)
    }

    /// What the server should send for this engine.
    private static func caps(for engine: PlaybackEngine) -> PlayerCaps {
        engine is MPVEngine ? DeviceCaps.mpv() : DeviceCaps.apple()
    }

    private func switchToApple() {
        engine.onEvent = nil
        engine.stop()
        let apple = AVPlayerEngine()
        apple.onEvent = { [weak self] in self?.handle($0) }
        engine = apple
        caps = DeviceCaps.apple()
        if speed != 1 { apple.setRate(speed) }
        if zoomed { apple.setZoom(true) }
        retried = false
    }

    /// Playback Info's rows, as Android's: how it's playing and why, the picture and sound as
    /// played (the engine's own reading, else the file's), and how the stream is arriving.
    func infoRows() -> [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []
        let stats = engine.stats
        let p = plan
        rows.append((L("stats.playing"), [methodName, engineName].compactMap { $0 }.joined(separator: " · ")))
        if let reasons = p?.reasons, !reasons.isEmpty { rows.append((L("stats.reason"), reasons.joined(separator: ", "))) }
        let file = p.flatMap { plan in item.files.first { $0.id == plan.fileId } } ?? Quality.file(of: item)
        let source = file?.streams.first { $0.kind == "video" }
        let converted = p?.method == "transcode"
        let codec = stats.videoCodec ?? (converted ? nil : source?.codec)
        let width = stats.width > 0 ? stats.width : converted ? 0 : source?.width ?? 0
        let height = stats.height > 0 ? stats.height : converted ? 0 : source?.height ?? 0
        if let video = StatsFormat.video(codec: codec, width: width, height: height, frameRate: stats.frameRate ?? source?.frameRate) {
            rows.append((L("stats.video"), video))
        }
        let range = stats.transfer != nil || stats.dolbyVisionProfile != nil
            ? StatsFormat.dynamicRange(transfer: stats.transfer, dolbyVisionProfile: stats.dolbyVisionProfile)
            : converted ? "SDR" : StatsFormat.dynamicRange(transfer: source?.colorTransfer ?? (source == nil ? nil : "sdr"),
                                                           dolbyVisionProfile: source?.dolbyVisionProfile, dolbyVision: source?.dolbyVision ?? false)
        if let range { rows.append((L("stats.dynamic_range"), range)) }
        if let hardware = stats.hardwareDecoding { rows.append((L("stats.video_decoder"), L(hardware ? "stats.hardware" : "stats.software"))) }
        if let track = audioTracks.first(where: { $0.index == p?.audioStream }),
           let audio = StatsFormat.audio(codec: track.codec, channels: track.channels) {
            // What the engine is fed, when Arc converted the sound on the way.
            let fed = StatsFormat.audio(codec: stats.audioCodec, channels: stats.audioChannels)
            rows.append((L("stats.audio"), fed.map { $0.lowercased() != audio.lowercased() ? audio + " → " + $0 : audio } ?? audio))
        }
        if let apple = stats.audioToAppleDecoder {
            rows.append((L("stats.audio_output"), apple ? L("stats.audio_apple")
                                                        : L("stats.audio_pcm", StatsFormat.channelLayout(stats.audioChannels ?? 2))))
        }
        if let burned = p?.subtitleTracks.first(where: { $0.id == burn }) {
            rows.append((L("stats.subtitles"), L("stats.burned_in", burned.codec.uppercased())))
        }
        if let kbps = p?.sourceKbps, kbps > 0 { rows.append((L("stats.bitrate"), StatsFormat.mbps(kbps))) }
        if let kbps = stats.downloadKbps { rows.append((L("stats.download"), StatsFormat.mbps(kbps))) }
        if let buffered = stats.bufferedSeconds { rows.append((L("stats.buffer"), StatsFormat.seconds(buffered))) }
        if let waits = stats.waits { rows.append((L("stats.waits"), String(waits))) }
        if let dropped = stats.droppedFrames { rows.append((L("stats.dropped"), String(dropped))) }
        rows.append((L("stats.this_tv"), DeviceCaps.summary))
        return rows
    }

    /// What the TV should switch to for the stream being played: the file's own picture when it's
    /// sent as it is or repackaged, plain SDR when Arc converts the video (to H.264, tone-mapped).
    private func displayHint(for p: PlaybackPlan) -> DisplayHint? {
        guard p.method != "transcode" else { return .sdr }
        let file = item.files.first { $0.id == p.fileId } ?? Quality.file(of: item)
        guard let video = file?.streams.first(where: { $0.kind == "video" }) else { return nil }
        return DisplayHint(video)
    }

    func close() {
        startTask?.cancel()
        loops.forEach { $0.cancel() }
        loops = []
        if plan != nil && !ended { report("stopped") }
        engine.stop()
        if let sid = plan?.sessionId {
            let api = self.api
            Task.detached { await api.stopTranscode(sid) }
        }
    }

    private func keepAlive() async {
        guard let sid = plan?.sessionId else { return }
        do { try await api.pingTranscode(sid) } catch { log.debug("keeping the conversion alive failed: \(type(of: error))") }
    }

    /// Saves progress. Arc answers 403 when an admin ends this playback.
    private func report(_ state: String, position: Int64? = nil) {
        let duration = durationMs
        guard duration > 0 else { return }
        lastReport = Date()
        let report = ProgressReport(positionMs: min(max(0, position ?? positionMs), duration), durationMs: duration, state: state)
        let api = self.api
        let id = item.id
        Task { [weak self] in
            do {
                try await api.reportProgress(itemId: id, report)
            } catch let error as APIError where error.status == 403 {
                self?.engine.pause()
                self?.fail(error.message)
            } catch {
                ArcLog.shared.warn("saving progress failed: \(type(of: error))")
            }
        }
    }
}
