import ArcKit
import AVFoundation
import SwiftUI
import UIKit

/// The player on iPhone and iPad, as iOS's own players feel: full screen and landscape on
/// iPhone. A tap shows or hides the controls, which hide by themselves after a few seconds of
/// playing. A double tap on either side skips 10 seconds. The timeline is dragged to scrub, and
/// pinching zooms the picture to fill. The controls are the same set and order as every Arc
/// player: close, title, subtitles and audio, then back 10, play/pause and forward 10, then the
/// timeline. Skip Intro and Up Next appear in the corner, as Plex's do.
struct MobilePlayerScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Browse.self) private var browse
    @Environment(\.dismiss) private var dismiss
    let request: PlayRequest

    @State private var model: PlayerModel?
    @State private var controls = true
    @State private var hideTask: Task<Void, Never>?
    @State private var nowPlaying = NowPlaying()
    /// Dragging the timeline: where the marker is.
    @State private var scrubMs: Double?
    @State private var countdown: Int?
    @State private var upNextDismissed = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let model {
                MobileEngineSurface(engine: model.engine)
                    .id(ObjectIdentifier(model.engine))
                    .ignoresSafeArea()
                if let caption = model.caption, model.subtitle?.image != true {
                    MobileSubtitleText(text: caption, style: model.prefs?.subtitleStyle, raised: controls)
                }
                gestures(model)
                if model.busy && model.problem == nil { ProgressView().controlSize(.large).tint(ArcColor.foreground) }
                if let problem = model.problem {
                    problemPane(problem, model)
                } else {
                    overlay(model)
                        .opacity(controls ? 1 : 0)
                        .allowsHitTesting(controls)
                        .animation(.easeInOut(duration: 0.2), value: controls)
                    corner(model)
                }
            }
        }
        .statusBarHidden(!controls)
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .onAppear(perform: begin)
        .onDisappear {
            hideTask?.cancel()
            nowPlaying.stop()
            model?.close()
            Orientation.release()
        }
        .modifier(MobilePlaybackChanges(playing: model?.playing ?? false, seekedAt: model?.seekedAt,
                                        durationMs: model?.durationMs ?? 0) { tellNowPlaying() })
        .onChange(of: model?.playing ?? false) { _, playing in if playing { scheduleHide() } else { hideTask?.cancel() } }
        .onChange(of: model?.ended ?? false) { _, ended in
            guard ended else { return }
            if let next = model?.next, playsOn, !upNextDismissed {
                playNext(next)
            } else {
                if model?.nextIsQueued != true { endQueue() }
                dismiss()
            }
        }
        .onChange(of: model?.upNextDue ?? false) { _, due in
            guard due, !upNextDismissed, playsOn else { return }
            startCountdown()
        }
    }

    // MARK: Starting

    private func begin() {
        guard model == nil, let api = app.api else { return }
        // Plays with the ring/silent switch on and over other audio, as a video app should.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        Orientation.landscapeOnPhone()
        let m = PlayerModel(api: api, item: request.item, startMs: request.startMs, fileId: request.fileId,
                            engine: EngineChoice.make()) { app.tokenRefused() }
        model = m
        m.start()
        Task { await syncQueue(m) }
        nowPlaying.start(m.item, durationMs: m.durationMs, api: api, actions: .init(
            toggle: { model?.togglePlay() },
            play: { if model?.playing == false { model?.togglePlay() } },
            pause: { if model?.playing == true { model?.togglePlay() } },
            skip: { model?.seek(by: $0) },
            seek: { model?.seek(toMs: $0) }))
        showControls()
    }

    // MARK: Touch

    /// Under the controls: a tap shows or hides them; a double tap on the left or right third
    /// skips 10 seconds; a pinch fills the screen or fits the picture.
    private func gestures(_ model: PlayerModel) -> some View {
        GeometryReader { g in
            Color.clear
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture(count: 2).onEnded { tap in
                    let x = tap.location.x
                    if x < g.size.width / 3 { model.seek(by: -10_000); showControls() }
                    else if x > g.size.width * 2 / 3 { model.seek(by: 10_000); showControls() }
                    else { model.togglePlay(); showControls() }
                }.exclusively(before: TapGesture().onEnded {
                    if controls { controls = false; hideTask?.cancel() } else { showControls() }
                }))
                .simultaneousGesture(MagnifyGesture().onEnded { value in
                    if value.magnification > 1.1, !model.zoomed { model.chooseZoom(true) }
                    else if value.magnification < 0.9, model.zoomed { model.chooseZoom(false) }
                })
        }
        .ignoresSafeArea()
    }

    // MARK: Controls

    private func overlay(_ model: PlayerModel) -> some View {
        ZStack {
            // A shade at the top and bottom so the white controls read over any picture.
            LinearGradient(stops: [.init(color: .black.opacity(0.65), location: 0), .init(color: .clear, location: 0.25),
                                   .init(color: .clear, location: 0.7), .init(color: .black.opacity(0.75), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            VStack(spacing: 0) {
                topBar(model)
                Spacer()
                centre(model)
                Spacer()
                timeline(model)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private func topBar(_ model: PlayerModel) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Button { close() } label: { roundIcon("xmark") }
                .accessibilityLabel(Text(L("common.close")))
                .accessibilityIdentifier("player.close")
            VStack(alignment: .leading, spacing: 2) {
                if model.item.isEpisode {
                    Text(model.item.seriesTitle ?? model.item.title).font(.headline).lineLimit(1)
                    Text(model.item.episodeLine).font(.subheadline).foregroundStyle(ArcColor.muted).lineLimit(1)
                } else {
                    Text(model.item.title).font(.headline).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            tracksMenu(model)
            moreMenu(model)
        }
        .foregroundStyle(ArcColor.foreground)
    }

    /// Subtitles and audio, as one menu (the speech bubble of iOS's players).
    private func tracksMenu(_ model: PlayerModel) -> some View {
        Menu {
            Section(L("player.subtitles")) {
                Button { model.chooseSubtitle(nil); showControls() } label: {
                    check(model.subtitle == nil, L("player.off"))
                }
                ForEach(model.subtitleTracks) { t in
                    Button { model.chooseSubtitle(t); showControls() } label: {
                        check(model.subtitle?.id == t.id, PlayerText.trackName(t))
                    }
                }
            }
            if model.audioTracks.count > 1 {
                Section(L("player.audio")) {
                    ForEach(model.audioTracks) { a in
                        Button { model.chooseAudio(a.index); showControls() } label: {
                            check(model.audioStream == a.index, PlayerText.audioName(a))
                        }
                    }
                }
            }
        } label: {
            roundIcon("captions.bubble")
        }
        .accessibilityLabel(Text(L("player.subtitles")))
        .disabled(model.loading)
    }

    /// Speed and zoom, under ⋯.
    private func moreMenu(_ model: PlayerModel) -> some View {
        Menu {
            Picker(L("player.speed"), selection: Binding(get: { model.speed }, set: { model.chooseSpeed($0); showControls() })) {
                ForEach(PlayerText.speeds, id: \.self) { Text(L("player.speed_value", PlayerText.speedName($0))).tag($0) }
            }
            .pickerStyle(.menu)
            Picker(L("player.zoom_mode"), selection: Binding(get: { model.zoomed }, set: { model.chooseZoom($0); showControls() })) {
                Text(L("player.zoom_normal")).tag(false)
                Text(L("player.zoom_fill")).tag(true)
            }
            .pickerStyle(.menu)
            if model.positionMs > 5_000 {
                Button { model.restart() } label: { Label(L("details.from_beginning"), systemImage: "arrow.counterclockwise") }
            }
        } label: {
            roundIcon("ellipsis")
        }
        .accessibilityLabel(Text(L("actions.more")))
    }

    private func centre(_ model: PlayerModel) -> some View {
        HStack(spacing: 56) {
            Button { model.seek(by: -10_000); showControls() } label: {
                Image(systemName: "gobackward.10").font(.system(size: 30, weight: .medium))
            }
            .accessibilityIdentifier("player.back10")
            Button { model.togglePlay(); showControls() } label: {
                Image(systemName: model.playing ? "pause.fill" : "play.fill").font(.system(size: 46))
                    .frame(width: 64, height: 64)
            }
            .accessibilityLabel(Text(model.playing ? L("mobile.pause") : L("details.play")))
            .accessibilityIdentifier("player.play")
            Button { model.seek(by: 10_000); showControls() } label: {
                Image(systemName: "goforward.10").font(.system(size: 30, weight: .medium))
            }
            .accessibilityIdentifier("player.forward10")
        }
        .foregroundStyle(ArcColor.foreground)
        .buttonStyle(.plain)
        .opacity(model.loading ? 0 : 1)
    }

    private func timeline(_ model: PlayerModel) -> some View {
        let duration = Double(max(model.durationMs, 1))
        let at = scrubMs ?? Double(model.positionMs)
        return VStack(spacing: 4) {
            Slider(value: Binding(get: { min(at, duration) }, set: { scrubMs = $0 }), in: 0...duration, onEditingChanged: { editing in
                if editing {
                    hideTask?.cancel()
                } else if let to = scrubMs {
                    model.seek(toMs: Int64(to))
                    scrubMs = nil
                    showControls()
                }
            })
            .disabled(model.loading || model.durationMs <= 0)
            .accessibilityIdentifier("player.timeline")
            HStack {
                Text(PlayerText.time(Int64(at)))
                Spacer()
                Text("-" + PlayerText.time(max(0, Int64(duration - at))))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(ArcColor.muted)
        }
    }

    private func roundIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 17, weight: .semibold))
            .frame(width: 40, height: 40)
            .background(Circle().fill(.black.opacity(0.35)))
            .contentShape(Circle())
    }

    @ViewBuilder private func check(_ on: Bool, _ title: String) -> some View {
        if on { Label(title, systemImage: "checkmark") } else { Text(title) }
    }

    /// Skip Intro / Skip Credits, or Up Next, at the bottom right above the timeline.
    @ViewBuilder private func corner(_ model: PlayerModel) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                if model.upNextDue, !upNextDismissed, let next = model.next {
                    upNext(next)
                } else if let marker = model.marker, marker.kind != "credits" || model.next == nil {
                    Button { model.skipMarker() } label: {
                        Text(L(marker.kind == "credits" ? "player.skip_credits" : marker.kind == "recap" ? "player.skip_recap" : "player.skip_intro"))
                            .font(.subheadline.weight(.semibold))
                    }
                    .arcGlassButton(prominent: true)
                    .accessibilityIdentifier("player.skip")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, controls ? 76 : 24)
        .animation(.easeInOut(duration: 0.2), value: controls)
    }

    private func upNext(_ next: Item) -> some View {
        HStack(spacing: 12) {
            ArtworkImage(path: next.images?.primary)
                .frame(width: 128, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(L("player.up_next")).font(.caption).foregroundStyle(ArcColor.muted)
                Text(next.episodeLine).font(.subheadline.weight(.semibold)).lineLimit(1)
                HStack(spacing: 8) {
                    Button { playNext(next) } label: {
                        Label(countdown.map { L("player.play_in", $0) } ?? L("player.play_now"), systemImage: "play.fill")
                            .font(.footnote.weight(.semibold))
                    }
                    .arcGlassButton(prominent: true)
                    Button(L("common.cancel")) {
                        upNextDismissed = true
                        countdown = nil
                    }
                    .font(.footnote)
                    .arcGlassButton()
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 380)
        .arcGlassPanel(cornerRadius: 16)
    }

    private func problemPane(_ message: String, _ model: PlayerModel) -> some View {
        VStack(spacing: 18) {
            Text(L("player.failed_title")).font(.title3.weight(.semibold))
            Text(message).foregroundStyle(ArcColor.muted).multilineTextAlignment(.center).frame(maxWidth: 480)
            HStack(spacing: 16) {
                Button(L("common.retry")) { model.retry() }.arcGlassButton(prominent: true)
                Button(L("common.close")) { close() }.arcGlassButton()
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.85))
    }

    // MARK: Behaviour

    private func showControls() {
        controls = true
        scheduleHide()
    }

    /// The controls hide after four seconds of playing, as iOS's players.
    private func scheduleHide() {
        hideTask?.cancel()
        guard model?.playing == true else { return }
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, scrubMs == nil, model?.playing == true else { return }
            controls = false
        }
    }

    private func tellNowPlaying() {
        guard let model else { return }
        nowPlaying.update(positionMs: model.positionMs, durationMs: model.durationMs, playing: model.playing)
    }

    private func close() { dismiss() }

    private func playNext(_ next: Item) {
        countdown = nil
        ArcLogApp.info("playing the next episode")
        let entry = model?.queued.flatMap { $0.item.id == next.id ? $0.entry : nil }
        browse.play(PlayRequest(item: next, startMs: next.resumeMs, playingOn: true, queueEntry: entry))
    }

    /// The next title plays by itself: Auto-Play is on, or it was queued on purpose.
    private var playsOn: Bool { model?.prefs?.autoPlay != false || model?.nextIsQueued == true }

    private func startCountdown() {
        countdown = 10
        Task { @MainActor in
            while let left = countdown, left > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard countdown != nil, !upNextDismissed else { return }
                countdown = left - 1
            }
            if countdown == 0, let next = model?.next { playNext(next) }
        }
    }

    /// Keeps Arc's play queue in step with what's playing, as the Apple TV's player does.
    private func syncQueue(_ m: PlayerModel) async {
        guard let api = app.api else { return }
        let item = request.item
        await browse.withQueue { queues in
            if let entry = request.queueEntry {
                await queues.moveTo(api, entry)
            } else if request.playingOn {
                await queues.carryOn(api, with: item.id)
            } else {
                await queues.start(api, [item.id])
            }
        }
        let next = browse.queue?.nextPlayable()
        m.setQueued(next?.item, entry: next?.id)
    }

    private func endQueue() {
        guard let api = app.api else { return }
        let browse = browse
        Task { await browse.withQueue { await $0.end(api) } }
    }
}

/// Which way the app may turn. The player turns an iPhone to landscape, as video apps do, and
/// gives the turn back when it closes; an iPad turns freely.
enum Orientation {
    @MainActor static var allowed: UIInterfaceOrientationMask = .allButUpsideDown

    @MainActor static func landscapeOnPhone() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        set(.landscape)
    }

    @MainActor static func release() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        set(.allButUpsideDown, prefer: .portrait)
    }

    @MainActor private static func set(_ mask: UIInterfaceOrientationMask, prefer: UIInterfaceOrientationMask? = nil) {
        allowed = mask
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: prefer ?? mask)) { _ in }
        }
    }
}

/// Answers iOS's question of which way the app may turn (Orientation decides).
final class MobileAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated { Orientation.allowed }
    }
}

private struct MobileEngineSurface: UIViewRepresentable {
    let engine: PlaybackEngine
    func makeUIView(context: Context) -> UIView { engine.view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// A line of subtitles in the profile's style (size, colour, background, top or bottom), sized
/// for a phone or tablet.
private struct MobileSubtitleText: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let text: String
    let style: SubtitleStyle?
    let raised: Bool

    var body: some View {
        let top = style?.position == "top"
        VStack {
            if !top { Spacer() }
            Text(text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(style?.color == "yellow" ? ArcColor.subtitleYellow : Color.white)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(style?.background == "none" ? 0.9 : 0.5), radius: style?.background == "none" ? 2 : 1)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(background)
            if top { Spacer() }
        }
        .padding(.horizontal, 40)
        .padding(top ? .top : .bottom, top ? 24 : (raised ? 90 : 24))
        .animation(.easeInOut(duration: 0.2), value: raised)
        .allowsHitTesting(false)
    }

    private var size: CGFloat {
        let base: CGFloat = sizeClass == .regular ? 28 : 20
        switch style?.size {
        case "small": return base * 0.8
        case "large": return base * 1.25
        case "huge": return base * 1.55
        default: return base
        }
    }

    @ViewBuilder private var background: some View {
        switch style?.background {
        case "solid": RoundedRectangle(cornerRadius: 4).fill(.black)
        case "none": Color.clear
        default: RoundedRectangle(cornerRadius: 4).fill(.black.opacity(0.65))
        }
    }
}

private struct MobilePlaybackChanges: ViewModifier {
    let playing: Bool
    let seekedAt: Date?
    let durationMs: Int64
    let changed: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: playing) { _, _ in changed() }
            .onChange(of: seekedAt) { _, _ in changed() }
            .onChange(of: durationMs) { _, _ in changed() }
    }
}
