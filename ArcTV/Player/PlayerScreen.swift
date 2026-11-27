import ArcKit
import SwiftUI

/// The player: the picture, a spinner while it waits, and Arc's own controls (PlayerOSD).
/// Play/Pause and the touch surface's click toggle playing; Left and Right clicks skip 10
/// seconds; a sideways swipe on the touch surface scrubs (paused, with the timeline picture),
/// and a click or Play plays from there while Back puts it back. Up goes to the round buttons,
/// Down to the cards, and Back closes those, hides the controls or closes the player. Skip Intro
/// and Up Next appear as Plex's do, with the focus on them.
struct PlayerScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Browse.self) private var browse
    @Environment(\.dismiss) private var dismiss
    let request: PlayRequest

    @State private var model: PlayerModel?
    @State private var controls = true
    /// The card open from the tab row, and whether the
    /// buttons and tabs have the focus (after Up or Down from the picture).
    @State private var tab: OSDTab?
    @State private var osdActive = false
    /// One of the round buttons' menus (tvOS's own) is open: the focus is in it, out of this
    /// screen's reach.
    private var menuOpen: Bool { osdActive && focus == nil }
    @State private var hideTask: Task<Void, Never>?
    /// Control Center, the Now Playing screen and the system's media commands.
    @State private var nowPlaying = NowPlaying()
    /// Scrubbing (a swipe across the remote's touch surface): where the marker is now, where the
    /// swipe started from, and whether it was playing (it plays on from the new point).
    @State private var scrubMs: Int64?
    @State private var scrubBase: Int64 = 0
    @State private var scrubResume = false
    /// When the last swipe moved: the move commands a swipe also sends are ignored for a moment.
    @State private var swipedAt = Date.distantPast
    /// Seconds left before the next episode starts (Auto-Play); nil when not counting.
    @State private var countdown: Int?
    @State private var upNextDismissed = false
    @FocusState private var focus: PlayerFocus?
    /// Watch Together: the lobby has gone (the room has played), and the loop that follows the room.
    @State private var lobbyDone = false
    @State private var follow: Task<Void, Never>?
    @State private var owner = UUID()

    enum PlayerFocus: Hashable { case surface, skip, upNext, lobbyStart, option(String), control(OSDMenu), tab(OSDTab), chapter(Int) }

    private var together: WatchTogetherModel { browse.together }
    /// The room this player follows, while it's in one.
    private var room: WatchRoom? { request.together ? together.room : nil }
    /// The lobby shows until the room first plays (or was under way when this player joined).
    private var lobby: Bool { room.map { $0.available && !lobbyDone } ?? false }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let model {
                EngineSurface(engine: model.engine).ignoresSafeArea()
                    // A new surface when Apple's player takes over from mpv.
                    .id(ObjectIdentifier(model.engine))
                if let caption = model.caption, model.subtitle?.image != true {
                    SubtitleText(text: caption, style: model.prefs?.subtitleStyle, raised: controls, cardOpen: controls && tab != nil)
                }
                if let problem = model.problem {
                    ProblemPane(message: problem, retry: { model.retry() }, close: { close() })
                } else {
                    // The surface takes the remote while nothing else has the focus.
                    Color.clear
                        .contentShape(Rectangle())
                        .focusable(!osdActive && !menuOpen && !lobby && together.inviting == nil)
                        .focused($focus, equals: .surface)
                        .onMoveCommand { move($0) }
                        .onTapGesture {
                            if scrubMs != nil { endScrub(commit: true) } else { togglePlay() }
                            showControls()
                        }
                    SwipeCatcher(enabled: !osdActive && !menuOpen && !lobby && !model.loading && model.problem == nil
                                    && together.inviting == nil && model.durationMs > 0,
                                 began: { beginScrub() },
                                 changed: { scrub($0) },
                                 ended: { swipedAt = Date() })
                        .frame(width: 0, height: 0)
                        .allowsHitTesting(false)
                    if model.loading || model.waiting { ProgressView().scaleEffect(1.6) }
                    PlayerOSD(model: model, room: room, tab: tab, active: osdActive, scrubMs: scrubMs, focus: $focus,
                              jump: { c in model.jump(to: c); sendSeek(); leaveOSD() },
                              play: { playNext($0) },
                              restart: { model.restart(); sendSeek(); leaveOSD() },
                              invite: { if let room { inviteMore(room) } },
                              leave: { close() },
                              end: { Task { await together.end() } },
                              down: {
                                  // After tvOS's own move, in case it found something below.
                                  Task { @MainActor in
                                      if case .control = focus { leaveOSD() }
                                  }
                              })
                        .opacity(controls ? 1 : 0)
                        .animation(.easeInOut(duration: 0.25), value: controls)
                    corner(model)
                    if model.showsInfo {
                        PlaybackInfoPanel(model: model)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(.top, 60)
                            .padding(.trailing, 80)
                            .ignoresSafeArea()
                            .transition(.opacity)
                    }
                    if let room, lobby {
                        LobbyPanel(room: room, code: together.lobbyCode, focus: $focus,
                                   start: { Task { await together.play() } },
                                   invite: { inviteMore(room) },
                                   leave: { close() })
                    }
                    if request.together, let target = together.inviting {
                        InvitePanel(target: target)
                    }
                }
            }
            if request.together, let notice = together.notice { NoticeCapsule(text: notice) }
        }
        .animation(.easeInOut(duration: 0.25), value: together.notice)
        .onPlayPauseCommand {
            if scrubMs != nil { endScrub(commit: true, play: true) } else { togglePlay() }
            showControls()
        }
        .onExitCommand {
            if scrubMs != nil {
                // Back puts the marker where it was.
                endScrub(commit: false)
            } else if request.together && together.inviting != nil {
                together.inviting = nil
            } else if osdActive {
                leaveOSD()
            } else if controls && model?.playing == true && !lobby {
                controls = false
            } else {
                close()
            }
        }
        .onAppear {
            guard model == nil, let api = app.api else { return }
            let m = PlayerModel(api: api, item: request.item, startMs: request.startMs, fileId: request.fileId, engine: EngineChoice.make()) { app.tokenRefused() }
            model = m
            m.start()
            Task { await syncQueue(m) }
            nowPlaying.start(m.item, durationMs: m.durationMs, api: api, actions: .init(
                toggle: { togglePlay(); showControls() },
                play: { if model?.playing == false { togglePlay() } },
                pause: { if model?.playing == true { togglePlay() } },
                skip: { seek(by: $0); showControls() },
                seek: { ms in
                    model?.seek(toMs: ms)
                    sendSeek()
                }))
            focus = .surface
            showControls()
            if request.together { startFollowing(m) }
        }
        .onDisappear {
            hideTask?.cancel()
            follow?.cancel()
            if together.reporterOwner == owner { together.reporter = nil }
            nowPlaying.stop()
            model?.close()
        }
        // tvOS runs Now Playing's clock itself; it's told again when playing starts or stops, on
        // a jump, and when the length is known.
        .modifier(PlaybackChanges(playing: model?.playing ?? false, seekedAt: model?.seekedAt,
                                  durationMs: model?.durationMs ?? 0) { tellNowPlaying() })
        .onChange(of: model?.ended ?? false) { _, ended in
            guard ended else { return }
            if let room {
                // In a room the host's Up Next moves everyone on; the others wait for the room.
                if room.isHost, let next = model?.next, model?.prefs?.autoPlay != false, !upNextDismissed { playNext(next) }
                return
            }
            if let next = model?.next, playsOn, !upNextDismissed {
                playNext(next)
            } else {
                // Played to its end with nothing queued after it: Arc forgets the queue. (Back
                // keeps it, so more can be added from Home.)
                if model?.nextIsQueued != true { endQueue() }
                dismiss()
            }
        }
        .onChange(of: together.room) { _, now in
            guard request.together, let now else { return }
            if !lobbyDone && (now.state != "paused" || now.positionMs > 0) {
                lobbyDone = true
                focus = .surface
                showControls()
            }
        }
        .onChange(of: focus) { _, now in
            switch now {
            case .tab(let t):
                if tab != t { tab = t }
            case .control:
                tab = nil
            case .surface:
                if osdActive { osdActive = false; tab = nil }
            default:
                break
            }
            if osdActive { showControls() }
        }
        .onChange(of: lobby) { _, showing in
            if showing { Task { @MainActor in focus = .lobbyStart } }
        }
        // Skip Intro takes the focus when it appears, so Select skips (as Plex).
        .onChange(of: model?.marker?.startMs) { _, now in
            if now != nil, !menuOpen, !osdActive { focus = model?.marker?.kind == "credits" && model?.next != nil ? .upNext : .skip }
            else if focus == .skip { focus = .surface }
        }
        .onChange(of: model?.upNextDue ?? false) { _, due in
            guard due, !upNextDismissed, !menuOpen, room?.isHost ?? true else { return }
            focus = .upNext
            if playsOn { startCountdown() }
        }
    }

    /// On the picture: Left and Right skip 10 s, Up goes to the round buttons (Subtitles), Down opens the
    /// Info card (its tab focused), as the reference player.
    private func move(_ direction: MoveCommandDirection) {
        // A swipe sends move commands too; it scrubs instead.
        if direction == .left || direction == .right, Date().timeIntervalSince(swipedAt) < 0.5 { return }
        // Up or Down leaves scrubbing for the buttons or the cards, the marker back where it was.
        if direction == .up || direction == .down, scrubMs != nil { endScrub(commit: false) }
        switch direction {
        case .left where scrubMs != nil: nudgeScrub(-10_000)
        case .right where scrubMs != nil: nudgeScrub(10_000)
        case .left: seek(by: -10_000)
        case .right: seek(by: 10_000)
        case .up:
            osdActive = true
            Task { @MainActor in focus = .control(.subtitles) }
        case .down:
            osdActive = true
            tab = .info
            Task { @MainActor in focus = .tab(.info) }
        default: break
        }
        showControls()
    }

    // MARK: - Scrubbing

    /// A sideways swipe began: the video pauses and the marker moves with the finger, from where
    /// the last swipe left it.
    private func beginScrub() {
        guard let model else { return }
        swipedAt = Date()
        if scrubMs == nil {
            scrubResume = model.playing
            if model.playing { togglePlay() }
        }
        scrubBase = scrubMs ?? model.positionMs
        scrubMs = scrubBase
        showControls()
    }

    /// The finger has moved `dx` points since the swipe began. A swipe right across the whole
    /// surface moves about a quarter of the title (at least 2.5 minutes), as tvOS's players.
    private func scrub(_ dx: CGFloat) {
        guard let model, scrubMs != nil else { return }
        swipedAt = Date()
        let span = Double(max(model.durationMs, 600_000)) / 4
        let moved = Int64(Double(dx) / 1920 * span)
        scrubMs = min(max(0, scrubBase + moved), max(0, model.durationMs - 1_000))
    }

    /// Left and Right clicks while scrubbing move the marker 10 seconds.
    private func nudgeScrub(_ deltaMs: Int64) {
        guard let model, let at = scrubMs else { return }
        scrubMs = min(max(0, at + deltaMs), max(0, model.durationMs - 1_000))
        showControls()
    }

    /// Select or Play plays from the marker; Back puts it back. Either way the video plays on if
    /// it was playing before the swipe (Play/Pause always plays).
    private func endScrub(commit: Bool, play: Bool = false) {
        guard let model, let at = scrubMs else { return }
        scrubMs = nil
        if commit {
            model.seek(toMs: at)
            sendSeek()
        }
        if (scrubResume || play) && !model.playing { togglePlay() }
        scrubResume = false
    }

    /// Back to the picture: menus and cards close, and the remote skips and pauses again.
    private func tellNowPlaying() {
        guard let model else { return }
        nowPlaying.update(positionMs: model.positionMs, durationMs: model.durationMs, playing: model.playing)
    }

    private func leaveOSD() {
        tab = nil
        osdActive = false
        focus = .surface
        showControls()
    }

    /// Skip Intro / Skip Credits, or the Up Next card.
    @ViewBuilder private func corner(_ model: PlayerModel) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                if model.upNextDue, !upNextDismissed, room?.isHost ?? true, let next = model.next {
                    UpNextCard(next: next, countdown: countdown, focus: $focus, play: { playNext(next) }, dismiss: {
                        upNextDismissed = true
                        countdown = nil
                        focus = .surface
                    })
                } else if let marker = model.marker, marker.kind != "credits" || model.next == nil {
                    Button { model.skipMarker(); sendSeek(); focus = .surface } label: {
                        Text(L(marker.kind == "credits" ? "player.skip_credits" : marker.kind == "recap" ? "player.skip_recap" : "player.skip_intro"))
                            .font(.headline)
                    }
                    .arcGlassButton()
                    .focused($focus, equals: .skip)
                }
            }
        }
        // From the screen's edges, lined up with the controls' right edge.
        .padding(.horizontal, 100)
        .padding(.bottom, controls ? 334 : 140)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.25), value: controls)
    }

    private func playNext(_ next: Item) {
        countdown = nil
        if room != nil {
            // The room moves on, and every player in it follows (this one included).
            ArcLogApp.info("moving the room to the next episode")
            Task { await together.changeItem(next.id) }
            return
        }
        ArcLogApp.info("playing the next episode")
        let entry = model?.queued.flatMap { $0.item.id == next.id ? $0.entry : nil }
        browse.play(PlayRequest(item: next, startMs: next.resumeMs, playingOn: true, queueEntry: entry))
    }

    /// The next title plays by itself: Auto-Play is on, or it was queued on purpose.
    private var playsOn: Bool { model?.prefs?.autoPlay != false || model?.nextIsQueued == true }

    // MARK: - Play queue

    /// Keeps Arc's play queue in step with what's playing, as the web player does: playing a
    /// title starts a new queue of it; one from the queue moves it there; Auto-Play's next episode
    /// is added to the end. Then the queue's next title becomes Up Next. (Not in Watch Together,
    /// where the room decides.)
    private func syncQueue(_ m: PlayerModel) async {
        guard !request.together, let api = app.api else { return }
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
        guard !request.together, let api = app.api else { return }
        let browse = browse
        Task { await browse.withQueue { await $0.end(api) } }
    }

    // MARK: - Watch Together

    /// Play/Pause: in a room it goes to the room (and plays or pauses here at once).
    private func togglePlay() {
        guard let model else { return }
        guard let room else { model.togglePlay(); return }
        if room.state == "playing" {
            model.setPlaying(false)
            Task { await together.pause() }
        } else {
            model.setPlaying(true)
            Task { await together.play() }
        }
    }

    /// Moves here at once, and takes the room there.
    private func seek(by deltaMs: Int64) {
        guard !lobby else { return }
        model?.seek(by: deltaMs)
        sendSeek()
    }

    private func sendSeek() {
        guard room != nil, let ms = model?.positionMs else { return }
        Task { await together.seek(toMs: ms) }
    }

    private func inviteMore(_ room: WatchRoom) {
        guard let id = room.itemId else { return }
        tab = nil
        together.inviting = .init(itemId: id, title: room.item?.title ?? model?.item.title ?? "", roomId: room.id)
    }

    /// Closing the player leaves the room (the others carry on).
    private func close() {
        if request.together { together.leave() }
        dismiss()
    }

    /// Reports this player to the room, and keeps it in step: plays and pauses with the room,
    /// plays a little faster or slower to catch up, and jumps when it's far out.
    private func startFollowing(_ m: PlayerModel) {
        if room.map({ $0.state != "paused" || $0.positionMs > 0 }) == true { lobbyDone = true }
        together.reporterOwner = owner
        together.reporter = {
            RoomReport(positionMs: m.positionMs, state: m.busy ? "waiting" : (m.playing ? "playing" : "paused"), ready: !m.loading)
        }
        let together = self.together, itemId = request.item.id
        follow = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let room = together.room, room.available, room.itemId == itemId, !m.loading else { continue }
                let expected = together.expectedMs()
                if room.state == "playing" {
                    if !m.playing { m.setPlaying(true) }
                    switch WatchSync.correction(localMs: Double(m.positionMs), expectedMs: expected) {
                    case .none: m.setRate(1)
                    case .rate(let rate): m.setRate(Float(rate))
                    case .seek(let to):
                        m.setRate(1)
                        m.seek(toMs: Int64(to))
                    }
                } else {
                    // Paused, or waiting for someone to load: hold here, at the room's place.
                    if m.playing { m.setPlaying(false) }
                    m.setRate(1)
                    if abs(Double(m.positionMs) - expected) > 1500 { m.seek(toMs: Int64(expected)) }
                }
            }
        }
    }

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

    /// Shows the controls, and hides them again after a quiet spell: 4 s, or 9 s with a card up,
    /// as the reference player. Never while a menu is open or the video is paused. If the
    /// buttons had the focus, it goes back to the picture first.
    private func showControls() {
        controls = true
        hideTask?.cancel()
        let quiet: Duration = tab != nil ? .seconds(9) : .seconds(4)
        hideTask = Task {
            try? await Task.sleep(for: quiet)
            guard !Task.isCancelled, model?.playing == true, !menuOpen, !lobby else { return }
            if osdActive {
                osdActive = false
                tab = nil
                focus = .surface
            }
            controls = false
        }
    }

}

/// The next episode near the end: its picture and name, Play Now and the countdown.
private struct UpNextCard: View {
    let next: Item
    let countdown: Int?
    var focus: FocusState<PlayerScreen.PlayerFocus?>.Binding
    let play: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 28) {
            ArtworkImage(path: next.images?.primary).frame(width: 320, height: 180).clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 10) {
                Text(L("player.up_next")).font(.caption).foregroundStyle(ArcColor.muted)
                Text(next.episodeLine)
                    .font(.headline).lineLimit(2)
                HStack(spacing: 20) {
                    Button(action: play) {
                        Label(countdown.map { L("player.play_in", $0) } ?? L("player.play_now"), systemImage: "play.fill")
                    }
                    .arcGlassButton(prominent: true)
                    .focused(focus, equals: .upNext)
                    Button(L("common.cancel"), action: dismiss).arcGlassButton()
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
        }
        .padding(28)
        .arcGlassPanel()
    }
}

/// A line of subtitles in the profile's style (size, colour, background, top or bottom).
private struct SubtitleText: View {
    let text: String
    let style: SubtitleStyle?
    /// Lifted above the controls while they show.
    let raised: Bool
    /// A card is up from the tab row: the line moves to the top of the screen, out of its way.
    var cardOpen = false

    var body: some View {
        let top = style?.position == "top" || cardOpen
        VStack {
            if !top { Spacer() }
            Text(plain)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(style?.color == "yellow" ? Color(hex: 0xFFE14D) : Color.white)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(style?.background == "none" ? 0.9 : 0.5), radius: style?.background == "none" ? 3 : 1)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(background)
            if top { Spacer() }
        }
        .padding(.horizontal, 120)
        .padding(top ? .top : .bottom, top ? 70 : (raised ? 340 : 80))
        .animation(.easeInOut(duration: 0.25), value: raised)
        .allowsHitTesting(false)
    }

    private var size: CGFloat {
        switch style?.size {
        case "small": return 36
        case "large": return 58
        case "huge": return 72
        default: return 46
        }
    }

    @ViewBuilder private var background: some View {
        switch style?.background {
        case "solid": RoundedRectangle(cornerRadius: 6).fill(.black)
        case "none": Color.clear
        // The usual look (as the web's): a dark box behind the line.
        default: RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.65))
        }
    }

    /// The text without its <i>, <b> and <u> tags.
    private var plain: String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}

private struct EngineSurface: UIViewRepresentable {
    let engine: PlaybackEngine
    func makeUIView(context: Context) -> UIView { engine.view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// One timeline thumbnail, cut from its sheet, at 360 points wide.
struct TrickplayThumb: View {
    @Environment(AppModel.self) private var app
    let sheet: String
    let x: Int
    let y: Int
    let info: Trickplay.Info
    let chapter: String?
    @State private var image: UIImage?

    var body: some View {
        let scale = 360 / CGFloat(max(1, info.width))
        let height = CGFloat(info.height) * scale
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: CGFloat(info.width * info.columns) * scale, height: CGFloat(info.height * info.rows) * scale)
                        .offset(x: -CGFloat(x) * scale, y: -CGFloat(y) * scale)
                } else {
                    ArcColor.surface2
                }
            }
            .frame(width: 360, height: height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            if let chapter, !chapter.isEmpty {
                Text(chapter).font(.caption.weight(.semibold)).lineLimit(1).frame(width: 360, alignment: .leading)
            }
        }
        .frame(height: height, alignment: .bottom)
        .task(id: sheet) {
            guard let api = app.api, let url = api.absolute(sheet) else { return }
            image = await ArtworkLoader.shared.image(url, headers: api.authorization)
        }
    }
}

private struct ProblemPane: View {
    let message: String
    let retry: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Text(L("player.failed_title")).font(.title3.weight(.semibold))
            Text(message).foregroundStyle(ArcColor.muted).multilineTextAlignment(.center).frame(maxWidth: 900)
            HStack(spacing: 40) {
                Button(L("common.retry"), action: retry).arcGlassButton(prominent: true)
                Button(L("common.close"), action: close).arcGlassButton()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.85))
    }
}

/// Calls `changed` when playing starts or stops, after a jump, and when the length changes (its
/// own modifier, so the player's body stays small enough for the compiler).
private struct PlaybackChanges: ViewModifier {
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
