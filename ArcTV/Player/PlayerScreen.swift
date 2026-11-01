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

    enum PlayerFocus: Hashable { case surface, skip, upNext, option(String) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let model {
                EngineSurface(engine: model.engine).ignoresSafeArea()
                if let caption = model.caption, model.subtitle?.image != true {
                    SubtitleText(text: caption, style: model.prefs?.subtitleStyle, raised: controls || options)
                }
                if let problem = model.problem {
                    ProblemPane(message: problem, retry: { model.retry() }, close: { dismiss() })
                } else {
                    // The surface takes the remote while nothing else has the focus.
                    Color.clear
                        .contentShape(Rectangle())
                        .focusable(!options)
                        .focused($focus, equals: .surface)
                        .onMoveCommand { move($0) }
                        .onTapGesture { model.togglePlay(); showControls() }
                    if model.loading || model.waiting { ProgressView().scaleEffect(1.6) }
                    PlayerControls(model: model).opacity(controls && !options ? 1 : 0).animation(.easeInOut(duration: 0.25), value: controls)
                    corner(model)
                    if options { optionsPanel(model) }
                }
            }
        }
        .onPlayPauseCommand { model?.togglePlay(); showControls() }
        .onExitCommand {
            if options {
                options = false
                focus = .surface
            } else if controls && model?.playing == true {
                controls = false
            } else {
                dismiss()
            }
        }
        .onAppear {
            guard model == nil, let api = app.api else { return }
            let m = PlayerModel(api: api, item: request.item, startMs: request.startMs, engine: AVPlayerEngine()) { app.tokenRefused() }
            model = m
            m.start()
            focus = .surface
            showControls()
        }
        .onDisappear {
            hideTask?.cancel()
            model?.close()
        }
        .onChange(of: model?.ended ?? false) { _, ended in
            guard ended else { return }
            if let next = model?.next, model?.prefs?.autoPlay != false, !upNextDismissed { playNext(next) } else { dismiss() }
        }
        // Skip Intro takes the focus when it appears, so Select skips (as Plex).
        .onChange(of: model?.marker?.startMs) { _, now in
            if now != nil, !options { focus = model?.marker?.kind == "credits" && model?.next != nil ? .upNext : .skip }
            else if focus == .skip { focus = .surface }
        }
        .onChange(of: model?.upNextDue ?? false) { _, due in
            guard due, !upNextDismissed, !options else { return }
            focus = .upNext
            if model?.prefs?.autoPlay != false { startCountdown() }
        }
    }

    private func move(_ direction: MoveCommandDirection) {
        switch direction {
        case .left: model?.seek(by: -10_000)
        case .right: model?.seek(by: 10_000)
        case .down:
            if let model, !model.subtitleTracks.isEmpty || model.audioTracks.count > 1 {
                options = true
                focus = .option(model.subtitle.map { "s:" + $0.id } ?? "s:off")
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
                if model.upNextDue, !upNextDismissed, let next = model.next {
                    UpNextCard(next: next, countdown: countdown, focus: $focus, play: { playNext(next) }, dismiss: {
                        upNextDismissed = true
                        countdown = nil
                        focus = .surface
                    })
                } else if let marker = model.marker, marker.kind != "credits" || model.next == nil {
                    Button { model.skipMarker(); focus = .surface } label: {
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
            }
            .padding(36)
        }
        .scrollClipDisabled()
        .frame(width: 640)
        .arcGlassPanel(cornerRadius: 40)
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
        ArcLogApp.info("playing the next episode")
        browse.play(PlayRequest(item: next, startMs: next.resumeMs))
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
                if !model.subtitleTracks.isEmpty || model.audioTracks.count > 1 {
                    HStack(spacing: 14) {
                        if !model.subtitleTracks.isEmpty { glassIcon("captions.bubble") }
                        if model.audioTracks.count > 1 { glassIcon("speaker.wave.2") }
                        Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.7))
                    }
                    .accessibilityHidden(true)
                }
            }
            GeometryReader { geo in
                let fraction = model.durationMs > 0 ? min(1, Double(model.positionMs) / Double(model.durationMs)) : 0
                ZStack(alignment: .leading) {
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
