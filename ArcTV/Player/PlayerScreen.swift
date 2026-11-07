import ArcKit
import SwiftUI

/// The player: the picture, a spinner while it waits, and Arc's own controls (title, timeline,
/// times). Play/Pause and the touch surface's click toggle playing, left and right skip 10
/// seconds, down opens Subtitles and Audio, and Back closes those, hides the controls or closes
/// the player. Skip Intro and Up Next appear as Plex's do, with the focus on them.
struct PlayerScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Browse.self) private var browse
    @Environment(\.dismiss) private var dismiss
    let request: PlayRequest

    @State private var model: PlayerModel?
    @State private var controls = true
    @State private var options = false
    @State private var hideTask: Task<Void, Never>?
    /// Seconds left before the next episode starts (Auto-Play); nil when not counting.
    @State private var countdown: Int?
    @State private var upNextDismissed = false
    @FocusState private var focus: PlayerFocus?
    /// Watch Together: the lobby has gone (the room has played), and the loop that follows the room.
    @State private var lobbyDone = false
    @State private var follow: Task<Void, Never>?
    @State private var owner = UUID()

    enum PlayerFocus: Hashable { case surface, skip, upNext, lobbyStart, option(String) }

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
                    SubtitleText(text: caption, style: model.prefs?.subtitleStyle, raised: controls || options)
                }
                if let problem = model.problem {
                    ProblemPane(message: problem, retry: { model.retry() }, close: { close() })
                } else {
                    // The surface takes the remote while nothing else has the focus.
                    Color.clear
                        .contentShape(Rectangle())
                        .focusable(!options && !lobby && together.inviting == nil)
                        .focused($focus, equals: .surface)
                        .onMoveCommand { move($0) }
                        .onTapGesture { togglePlay(); showControls() }
                    if model.loading || model.waiting { ProgressView().scaleEffect(1.6) }
                    PlayerControls(model: model).opacity(controls && !options ? 1 : 0).animation(.easeInOut(duration: 0.25), value: controls)
                    corner(model)
                    if options { optionsPanel(model) }
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
        .onPlayPauseCommand { togglePlay(); showControls() }
        .onExitCommand {
            if request.together && together.inviting != nil {
                together.inviting = nil
            } else if options {
                options = false
                focus = .surface
            } else if controls && model?.playing == true && !lobby {
                controls = false
            } else {
                close()
            }
        }
        .onAppear {
            guard model == nil, let api = app.api else { return }
            let m = PlayerModel(api: api, item: request.item, startMs: request.startMs, engine: EngineChoice.make()) { app.tokenRefused() }
            model = m
            m.start()
            focus = .surface
            showControls()
            if request.together { startFollowing(m) }
        }
        .onDisappear {
            hideTask?.cancel()
            follow?.cancel()
            if together.reporterOwner == owner { together.reporter = nil }
            model?.close()
        }
        .onChange(of: model?.ended ?? false) { _, ended in
            guard ended else { return }
            if let room {
                // In a room the host's Up Next moves everyone on; the others wait for the room.
                if room.isHost, let next = model?.next, model?.prefs?.autoPlay != false, !upNextDismissed { playNext(next) }
                return
            }
            if let next = model?.next, model?.prefs?.autoPlay != false, !upNextDismissed { playNext(next) } else { dismiss() }
        }
        .onChange(of: together.room) { _, now in
            guard request.together, let now else { return }
            if !lobbyDone && (now.state != "paused" || now.positionMs > 0) {
                lobbyDone = true
                focus = .surface
                showControls()
            }
        }
        .onChange(of: lobby) { _, showing in
            if showing { Task { @MainActor in focus = .lobbyStart } }
        }
        // Skip Intro takes the focus when it appears, so Select skips (as Plex).
        .onChange(of: model?.marker?.startMs) { _, now in
            if now != nil, !options { focus = model?.marker?.kind == "credits" && model?.next != nil ? .upNext : .skip }
            else if focus == .skip { focus = .surface }
        }
        .onChange(of: model?.upNextDue ?? false) { _, due in
            guard due, !upNextDismissed, !options, room?.isHost ?? true else { return }
            focus = .upNext
            if model?.prefs?.autoPlay != false { startCountdown() }
        }
    }

    private func move(_ direction: MoveCommandDirection) {
        switch direction {
        case .left: seek(by: -10_000)
        case .right: seek(by: 10_000)
        case .down:
            if let model {
                options = true
                focus = .option(model.subtitleTracks.isEmpty ? "q:" + (model.maxKbps.map(String.init) ?? "original")
                                : model.subtitle.map { "s:" + $0.id } ?? "s:off")
            }
        default: break
        }
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
        .padding(.horizontal, 90)
        .padding(.bottom, controls ? 220 : 80)
        .animation(.easeInOut(duration: 0.25), value: controls)
    }

    /// Subtitles and Audio, from swiping down, as the web player's settings: a glass panel down
    /// the right-hand side, so the picture stays in view.
    private func optionsPanel(_ model: PlayerModel) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 32) {
                if let room {
                    optionSection(L("together.title")) {
                        PeopleList(room: room)
                        if room.isHost {
                            optionButton(L("together.invite"), selected: false, key: "t:invite") { inviteMore(room) }
                        }
                        optionButton(L("together.leave"), selected: false, key: "t:leave") { close() }
                        if room.isHost {
                            optionButton(L("together.end"), selected: false, key: "t:end") { Task { await together.end() } }
                        }
                    }
                }
                if !model.subtitleTracks.isEmpty {
                    optionSection(L("player.subtitles")) {
                        optionButton(L("player.off"), selected: model.subtitle == nil, key: "s:off") { model.chooseSubtitle(nil) }
                        ForEach(model.subtitleTracks) { t in
                            optionButton(trackName(t), selected: model.subtitle?.id == t.id, key: "s:" + t.id) { model.chooseSubtitle(t) }
                        }
                    }
                }
                if model.audioTracks.count > 1 {
                    optionSection(L("player.audio")) {
                        ForEach(model.audioTracks) { a in
                            optionButton(audioName(a), selected: model.audioStream == a.index, key: "a:\(a.index)") { model.chooseAudio(a.index) }
                        }
                    }
                }
                optionSection(L("player.quality")) {
                    optionButton(L("player.original"), selected: model.maxKbps == nil, key: "q:original") { model.chooseQuality(nil) }
                    ForEach(model.qualities, id: \.self) { kbps in
                        optionButton(qualityName(kbps), selected: model.maxKbps == kbps, key: "q:\(kbps)") { model.chooseQuality(kbps) }
                    }
                }
                if model.versions.count > 1 {
                    optionSection(L("player.version")) {
                        ForEach(model.versions) { v in
                            optionButton(v.label, selected: model.fileId == v.fileId, key: "v:\(v.fileId)") { model.chooseVersion(v.fileId) }
                        }
                    }
                }
                if !model.chapters.isEmpty {
                    optionSection(L("player.chapters")) {
                        ForEach(Array(model.chapters.enumerated()), id: \.offset) { i, c in
                            optionButton(chapterName(c, i), selected: model.chapter == c, key: "c:\(i)") {
                                model.jump(to: c)
                                sendSeek()
                                options = false
                                focus = .surface
                            }
                        }
                    }
                }
            }
            .padding(36)
        }
        .frame(width: 640)
        .frame(maxHeight: .infinity)
        .arcGlassPanel(cornerRadius: 40)
        .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
        .padding(.vertical, 60)
        .padding(.trailing, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private func optionSection<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline).foregroundStyle(ArcColor.muted)
            content()
        }
        .focusSection()
    }

    private func optionButton(_ title: String, selected: Bool, key: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Text(title).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "checkmark").opacity(selected ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
        }
        .arcGlassButton(prominent: selected)
        .buttonBorderShape(.capsule)
        .focused($focus, equals: .option(key))
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
        browse.play(PlayRequest(item: next, startMs: next.resumeMs))
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
        options = false
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

    private func showControls() {
        controls = true
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled && model?.playing == true { controls = false }
        }
    }

    private func chapterName(_ c: Chapter, _ index: Int) -> String {
        let s = Int(c.startMs / 1000)
        let time = s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
        let name = (c.title?.isEmpty == false ? c.title : nil) ?? L("player.chapter", index + 1)
        return name + " · " + time
    }

    private func trackName(_ t: SubtitleTrack) -> String {
        var parts = [languageName(t.language) ?? t.title ?? L("player.unknown_language")]
        if let title = t.title, !title.isEmpty, parts.first != title { parts.append(title) }
        if t.forced { parts.append(L("player.forced")) }
        if t.hearingImpaired { parts.append(L("player.sdh")) }
        return parts.joined(separator: " · ")
    }

    private func audioName(_ a: AudioTrack) -> String {
        var parts = [languageName(a.language) ?? a.title ?? L("player.unknown_language")]
        if !a.codec.isEmpty { parts.append(a.codec.uppercased()) }
        switch a.channels {
        case 0: break
        case 1: parts.append(L("player.mono"))
        case 2: parts.append(L("player.stereo"))
        default: parts.append("\(a.channels - 1).1")
        }
        return parts.joined(separator: " · ")
    }

    private func languageName(_ code: String?) -> String? {
        guard let code, !code.isEmpty, code != "und" else { return nil }
        return Locale.current.localizedString(forLanguageCode: code) ?? code
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
                Text(L("card.episode", next.seasonNumber ?? 0, next.episodeNumber ?? 0, next.title)).font(.headline).lineLimit(2)
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

    var body: some View {
        let top = style?.position == "top"
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
        .padding(top ? .top : .bottom, top ? 70 : (raised ? 260 : 80))
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

/// The title large at the bottom left, a thin timeline and the times, over a soft shade, as
/// the Android player; Down shows the subtitle and audio panel (the hint at the right says so).
private struct PlayerControls: View {
    let model: PlayerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    if model.item.isEpisode {
                        Text(L("card.episode_code", model.item.seasonNumber ?? 0, model.item.episodeNumber ?? 0) + " · " + (model.item.seriesTitle ?? ""))
                            .font(.callout.weight(.medium)).foregroundStyle(.white.opacity(0.8))
                        Text(model.item.title).font(.system(size: 52, weight: .bold)).lineLimit(1)
                    } else {
                        Text(model.item.title).font(.system(size: 52, weight: .bold)).lineLimit(1)
                    }
                }
                Spacer()
                HStack(spacing: 14) {
                    if !model.subtitleTracks.isEmpty { glassIcon("captions.bubble") }
                    if model.audioTracks.count > 1 { glassIcon("speaker.wave.2") }
                    glassIcon("slider.horizontal.3")
                    Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.7))
                }
                .accessibilityHidden(true)
            }
            GeometryReader { geo in
                let fraction = model.durationMs > 0 ? min(1, Double(model.positionMs) / Double(model.durationMs)) : 0
                ZStack(alignment: .leading) {
                    // The picture at this point, for a moment after moving through the timeline.
                    if let trick = model.trickplay, let at = model.seekedAt, Date().timeIntervalSince(at) < 3,
                       let spot = trick.thumbnail(at: model.positionMs) {
                        TrickplayThumb(sheet: spot.sheet, x: spot.x, y: spot.y, info: trick.info, chapter: model.chapter?.title)
                            .offset(x: min(max(0, geo.size.width * fraction - 180), geo.size.width - 360), y: -150)
                    }
                    Capsule().fill(.white.opacity(0.25)).frame(height: 6)
                    Capsule().fill(.white).frame(width: geo.size.width * fraction, height: 6)
                    Circle().fill(.white).frame(width: 18, height: 18)
                        .offset(x: geo.size.width * fraction - 9)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 18)
            HStack(spacing: 14) {
                Image(systemName: model.playing ? "pause.fill" : "play.fill")
                Text(time(model.positionMs)).monospacedDigit()
                Spacer()
                Text("-" + time(max(0, model.durationMs - model.positionMs))).monospacedDigit()
            }
            .font(.callout)
            .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 90)
        .padding(.bottom, 60)
        .background(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .frame(height: 360)
                .ignoresSafeArea()
        }
    }

    /// A small glass circle with an icon, showing what Down opens.
    private func glassIcon(_ name: String) -> some View {
        Image(systemName: name).font(.callout).frame(width: 64, height: 64).arcGlassPanel(cornerRadius: 32)
    }

    private func time(_ ms: Int64) -> String {
        let s = Int(ms / 1000)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// One timeline thumbnail, cut from its sheet, at 360 points wide.
private struct TrickplayThumb: View {
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
