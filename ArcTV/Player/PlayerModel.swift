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

    let engine: PlaybackEngine
    private let api: ArcAPI
    private var plan: PlaybackPlan?
    private var caps: PlayerCaps
    private var retried = false
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
        caps = DeviceCaps.current()
        positionMs = startMs
        engine.onEvent = { [weak self] in self?.handle($0) }
    }

    func start() {
        load(at: positionMs)
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
                let p = try await api.startPlayback(itemId: item.id, request: PlaybackRequest(caps: caps, startMs: fileMs))
                guard !Task.isCancelled else { return }
                plan = p
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

    /// Moves by `deltaMs` in the file: within the stream when it can, else a new stream from there.
    func seek(by deltaMs: Int64) {
        guard let p = plan, !loading else { return }
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
        caps = DeviceCaps.current()
        load(at: positionMs)
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
