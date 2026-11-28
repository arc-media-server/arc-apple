import ArcKit
import SwiftUI

/// The menus that open above the round buttons (right of the title), in their order.
enum OSDMenu: Hashable, CaseIterable {
    case playback, audio, subtitles

    var icon: String {
        switch self {
        case .playback: return "slider.horizontal.3"
        case .audio: return "waveform"
        case .subtitles: return "captions.bubble"
        }
    }

    var title: String {
        switch self {
        case .playback: return L("player.playback")
        case .audio: return L("player.audio")
        case .subtitles: return L("player.subtitles")
        }
    }
}

/// The cards that slide up from the bottom, chosen by the tab row under the timeline.
enum OSDTab: Hashable {
    case info, chapters, cast, episodes, together

    var title: String {
        switch self {
        case .info: return L("player.info")
        case .chapters: return L("player.chapters")
        case .cast: return L("player.cast")
        case .episodes: return L("player.episodes")
        case .together: return L("together.title")
        }
    }
}

/// The player's on-screen controls, in the reference design's arrangement:
/// - at the bottom left the title (for an episode, "S2 · E4 · its name" over the show's name), and
///   to its right three small round buttons, Playback, Audio and Subtitles, each opening a menu
///   above it;
/// - the timeline, split at the chapters, with the time played under its marker and the time
///   left at the right;
/// - the tab row under it (Info, Chapters, Cast, Episodes, and Watch Together in a room). Down
///   from the picture opens Info; a tab's card slides up while the title and timeline step aside.
/// The screen keeps the state (which tab, the focus); this view only draws it.
struct PlayerOSD: View {
    let model: PlayerModel
    let room: WatchRoom?
    /// The card open from the tab row, if any.
    let tab: OSDTab?
    /// Whether the buttons and tabs take the focus (after Up or Down from the picture).
    let active: Bool
    /// While swiping on the remote's touch surface: where the marker has been moved to (not
    /// yet played from).
    let scrubMs: Int64?
    var focus: FocusState<PlayerScreen.PlayerFocus?>.Binding
    let jump: (Chapter) -> Void
    /// Plays another episode (the Episodes card, the Info card's Previous).
    let play: (Item) -> Void
    let restart: () -> Void
    let invite: () -> Void
    let leave: () -> Void
    let end: () -> Void
    /// Down from the round buttons: back to the timeline (the picture taking the remote again),
    /// from where Down opens Info. Nothing focusable sits under the buttons for tvOS to find.
    var down: () -> Void = {}

    var body: some View {
        ZStack(alignment: .bottom) {
            // The lower part of the picture shades to near-black behind the controls, as the
            // system player's; the rest of the picture is left as it is.
            LinearGradient(stops: [.init(color: .clear, location: 0.4), .init(color: .black.opacity(0.5), location: 0.7),
                                   .init(color: .black.opacity(0.8), location: 1)], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 18) {
                Spacer(minLength: 0)
                // The title and the timeline step aside while a card is up; the tabs stay.
                if tab == nil {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .bottom, spacing: 32) {
                            title
                            Spacer(minLength: 0)
                            OSDTrackButtons(model: model, room: room, active: active, tab: tab, focus: focus, down: down)
                        }
                        timeline
                    }
                    .transition(.opacity)
                }
                tabRow
                if let tab {
                    card(tab)
                        // Up from a card goes back to its tab, as tvOS often finds nothing above
                        // a card (the tabs sit at the left) and the focus stuck in it.
                        .onMoveCommand { direction in
                            guard direction == .up else { return }
                            let before = focus.wrappedValue
                            Task { @MainActor in
                                if focus.wrappedValue == before, before != .tab(tab) { focus.wrappedValue = .tab(tab) }
                            }
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            // Measured from the screen's edges, not tvOS's safe area (which would add its own 80
            // points at the sides): the controls reach across the screen, as the reference's.
            .padding(.horizontal, 100)
            .padding(.bottom, 64)
            .ignoresSafeArea()
            .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.45), value: tab)
        }
    }

    // MARK: Title, buttons, timeline

    private var title: some View {
        let item = model.item
        return VStack(alignment: .leading, spacing: 6) {
            if item.isEpisode {
                // Outside the show's order, an episode has no "S2 · E4" in it: just its name.
                Text(model.outsideOrder ? item.title : item.episodeLine)
                    .font(.callout.weight(.medium)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
            }
            Text(item.isEpisode ? (item.seriesTitle ?? item.title) : item.title)
                .font(.system(size: 52, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
    }

    /// Where the marker is: the scrubbed-to point while swiping, else where it's playing.
    private var shownMs: Int64 { scrubMs ?? model.positionMs }

    /// The timeline's pieces, one per chapter (the whole film when there are none).
    private var segments: [(start: Int64, end: Int64)] {
        let d = model.durationMs
        guard d > 0 else { return [(0, 1)] }
        let starts = [0] + model.chapters.map(\.startMs).filter { $0 > 0 && $0 < d }.sorted()
        return starts.enumerated().map { i, s in (start: s, end: i + 1 < starts.count ? starts[i + 1] : d) }
    }

    private var timeline: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let pieces = segments
            let gap: CGFloat = pieces.count > 1 ? 8 : 0
            let usable = width - gap * CGFloat(pieces.count - 1)
            let total = Double(max(1, pieces.last?.end ?? 1))
            let widths = pieces.map { max(2, usable * CGFloat(Double($0.end - $0.start) / total)) }
            let x = markerX(widths: widths, gap: gap, pieces: pieces)
            ZStack(alignment: .topLeading) {
                HStack(spacing: gap) {
                    ForEach(Array(pieces.enumerated()), id: \.offset) { i, piece in
                        let done = min(1, max(0, Double(shownMs - piece.start) / Double(max(1, piece.end - piece.start))))
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.35))
                            Capsule().fill(.white).frame(width: widths[i] * done)
                        }
                        .frame(width: widths[i], height: 12)
                    }
                }
                .position(x: width / 2, y: 11)
                RoundedRectangle(cornerRadius: 3).fill(.white)
                    .frame(width: 6, height: 30)
                    .shadow(color: .black.opacity(0.35), radius: 3)
                    .position(x: x, y: 11)
                // The time played, under the marker, and the time left at the end.
                HStack(spacing: 10) {
                    Text(PlayerText.time(shownMs)).monospacedDigit()
                    Image(systemName: model.playing ? "pause.circle.fill" : "play.circle.fill")
                }
                .font(.callout.weight(.semibold))
                .fixedSize()
                .position(x: min(max(x, 60), width - 260), y: 48)
                Text("-" + PlayerText.time(max(0, model.durationMs - shownMs)))
                    .font(.callout.weight(.semibold)).monospacedDigit()
                    .frame(width: width, alignment: .trailing)
                    .position(x: width / 2, y: 48)
                // The picture at this point: while scrubbing, and for a moment after a skip.
                if let trick = model.trickplay, scrubMs != nil || model.seekedAt.map({ Date().timeIntervalSince($0) < 3 }) == true,
                   let spot = trick.thumbnail(at: shownMs) {
                    TrickplayThumb(sheet: spot.sheet, x: spot.x, y: spot.y, info: trick.info,
                                   chapter: model.chapters.last(where: { $0.startMs <= shownMs })?.title)
                        .fixedSize()
                        .position(x: min(max(x, 180), width - 180), y: -120)
                }
            }
            .foregroundStyle(.white)
        }
        .frame(height: 64)
        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
    }

    /// Where the marker sits: along the piece it's in, after the gaps before it.
    private func markerX(widths: [CGFloat], gap: CGFloat, pieces: [(start: Int64, end: Int64)]) -> CGFloat {
        var x: CGFloat = 0
        for (i, piece) in pieces.enumerated() {
            if shownMs < piece.end || i == pieces.count - 1 {
                let done = min(1, max(0, Double(shownMs - piece.start) / Double(max(1, piece.end - piece.start))))
                return x + widths[i] * done
            }
            x += widths[i] + gap
        }
        return x
    }

    // MARK: Tabs and cards

    private var tabs: [OSDTab] {
        var out: [OSDTab] = [.info]
        if !model.chapters.isEmpty { out.append(.chapters) }
        if !model.cast.isEmpty { out.append(.cast) }
        if model.seasonEpisodes.count > 1 { out.append(.episodes) }
        if room != nil { out.append(.together) }
        return out
    }

    private var tabRow: some View {
        HStack(spacing: 16) {
            ForEach(tabs, id: \.self) { t in
                Button(t.title) {}
                    .buttonStyle(OSDTabStyle(chosen: tab == t))
                    .focused(focus, equals: .tab(t))
                    .disabled(!active)
            }
        }
        .focusSection()
    }

    @ViewBuilder private func card(_ tab: OSDTab) -> some View {
        switch tab {
        case .info: panel { infoCard }
        case .chapters: chaptersCard.frame(height: 240)
        case .cast: castCard.frame(height: 260)
        // The episodes scroll sideways under the panel's edge, not past it (the panel's 24-point
        // border leaves room for a focused card's lift).
        case .episodes: panel { episodesCard }.clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        case .together: panel { togetherCard }
        }
    }

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(24)
            .arcGlassPanel(cornerRadius: 32)
            .focusSection()
    }

    private var infoCard: some View {
        let item = model.item
        return HStack(alignment: .top, spacing: 28) {
            ArtworkImage(path: item.images?.primary ?? item.images?.backdrop)
                .frame(width: 320, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 20) {
                    Text(item.title).font(.title3.weight(.bold)).lineLimit(1)
                    Spacer(minLength: 0)
                    HStack(spacing: 14) {
                        Button(action: restart) {
                            Image(systemName: "arrow.counterclockwise").accessibilityLabel(L("player.restart"))
                        }
                        .buttonStyle(OSDIconStyle(size: 46))
                        .focused(focus, equals: .option("i:restart"))
                        if let previous = model.previous {
                            Button { play(previous) } label: {
                                Image(systemName: "backward.end.fill").accessibilityLabel(L("player.previous"))
                            }
                            .buttonStyle(OSDIconStyle(size: 46))
                            .focused(focus, equals: .option("i:previous"))
                        }
                    }
                }
                if let overview = item.overview, !overview.isEmpty {
                    Text(overview).font(.callout).foregroundStyle(.white.opacity(0.85)).lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    Text(meta).font(.caption.weight(.semibold)).lineLimit(1)
                    ForEach(Array(Quality.capsules(Quality.file(of: item)).enumerated()), id: \.offset) {
                        QualityCapsule(capsule: $0.element)
                    }
                    Spacer(minLength: 16)
                    // How it's reaching this Apple TV.
                    Text([model.methodName, model.engineName].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption2.weight(.medium)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
            }
        }
        .frame(height: 180)
    }

    /// "S2 · E4 · 24m · 24 Oct 2026" (a film: its year and length).
    private var meta: String {
        let item = model.item
        var parts: [String] = []
        if !model.outsideOrder, let code = item.episodeCodeText { parts.append(code) }
        let minutes = Int(model.durationMs / 60_000)
        if minutes > 0 {
            parts.append(minutes >= 60 ? L("details.runtime", minutes / 60, minutes % 60) : L("card.minutes_short", minutes))
        }
        if let date = item.releaseDate.flatMap(PlayerOSD.day) {
            parts.append(date)
        } else if let year = item.year {
            parts.append(String(year))
        }
        return parts.joined(separator: " · ")
    }

    private var chaptersCard: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 20) {
                ForEach(Array(model.chapters.enumerated()), id: \.offset) { i, c in
                    Button { jump(c) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Spacer(minLength: 0)
                            Text((c.title?.isEmpty == false ? c.title : nil) ?? L("player.chapter", i + 1))
                                .font(.caption.weight(.semibold)).lineLimit(2)
                            HStack(spacing: 8) {
                                Text(PlayerText.time(c.startMs)).font(.caption).monospacedDigit()
                                if model.chapter?.startMs == c.startMs {
                                    Image(systemName: "play.fill").font(.caption2)
                                }
                            }
                        }
                        .padding(18)
                        .frame(width: 180, height: 200, alignment: .bottomLeading)
                    }
                    .buttonStyle(OSDCardStyle())
                    .focused(focus, equals: .chapter(i))
                }
            }
            .padding(.vertical, 14)
        }
        .scrollClipDisabled()
        .focusSection()
    }

    private var castCard: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 20) {
                ForEach(Array(model.cast.enumerated()), id: \.offset) { i, person in
                    Button {} label: {
                        VStack(spacing: 8) {
                            ZStack {
                                ArcColor.surface2
                                ArtworkImage(path: person.image)
                            }
                            .frame(width: 118, height: 118)
                            .clipShape(Circle())
                            Text(person.name).font(.caption.weight(.semibold)).lineLimit(1)
                            if let character = person.character, !character.isEmpty {
                                Text(character).font(.caption2).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.top, 16)
                        .padding(.horizontal, 12)
                        .frame(width: 180, height: 220)
                    }
                    .buttonStyle(OSDCardStyle())
                    .focused(focus, equals: .option("c:\(i)"))
                }
            }
            .padding(.vertical, 14)
        }
        .scrollClipDisabled()
        .focusSection()
    }

    /// The Episodes card's height: a 169-point picture, its name under it, and room around them.
    static var episodesHeight: CGFloat { 240 }

    private var episodesCard: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 32) {
                    ForEach(model.seasonEpisodes) { episode in
                        VStack(alignment: .leading, spacing: 10) {
                            Button { if episode.id != model.item.id { play(episode) } } label: {
                                ArtworkImage(path: episode.images?.primary ?? episode.images?.backdrop)
                                    .frame(width: 300, height: 169)
                                    .overlay(alignment: .bottomLeading) {
                                        Text(model.outsideOrder ? "" : episode.episodeCodeText ?? "")
                                            .font(.caption2.weight(.bold))
                                            .shadow(color: .black.opacity(0.8), radius: 3)
                                            .padding(12)
                                    }
                            }
                            .buttonStyle(.card)
                            .focused(focus, equals: .option("e:" + episode.id))
                            Text(episode.title).font(.caption.weight(.semibold)).lineLimit(1).frame(width: 300, alignment: .leading)
                        }
                        .id(episode.id)
                    }
                }
                .padding(.vertical, 10)
            }
            .scrollClipDisabled()
            // A sideways scroll view takes all the height it's offered, which stretched the glass
            // panel down the screen: the picture, its name and the focus lift, no more.
            .frame(height: Self.episodesHeight)
            .onAppear { reader.scrollTo(model.item.id, anchor: .center) }
        }
    }

    @ViewBuilder private var togetherCard: some View {
        if let room {
            HStack(alignment: .top, spacing: 40) {
                PeopleList(room: room).frame(maxWidth: 560, alignment: .leading)
                VStack(alignment: .leading, spacing: 16) {
                    if room.isHost {
                        Button(L("together.invite"), action: invite).arcGlassButton().focused(focus, equals: .option("t:invite"))
                    }
                    Button(L("together.leave"), action: leave).arcGlassButton().focused(focus, equals: .option("t:leave"))
                    if room.isHost {
                        Button(L("together.end"), action: end).arcGlassButton().focused(focus, equals: .option("t:end"))
                    }
                }
            }
        }
    }

    static let speeds = PlayerText.speeds
}

/// A small round glass button with an icon: white with a black icon when focused.
struct OSDIconStyle: ButtonStyle {
    var size: CGFloat = 54
    @Environment(\.isFocused) private var focused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.38, weight: .semibold))
            .frame(width: size, height: size)
            .foregroundStyle(focused ? .black : .white)
            .background {
                if focused {
                    Circle().fill(.white)
                } else {
                    GlassFill(shape: Circle())
                }
            }
            .scaleEffect(focused ? 1.12 : 1)
            .shadow(color: .black.opacity(focused ? 0.35 : 0), radius: 8, y: 3)
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

/// A glass tile in the Chapters and Cast cards: it lifts and brightens when focused.
struct OSDCardStyle: ButtonStyle {
    @Environment(\.isFocused) private var focused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background {
                GlassFill(shape: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.white.opacity(focused ? 0.22 : 0)))
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(focused ? 0.6 : 0), lineWidth: 1))
            }
            .scaleEffect(focused ? 1.08 : 1)
            .shadow(color: .black.opacity(focused ? 0.4 : 0.15), radius: focused ? 16 : 6, y: focused ? 8 : 3)
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

/// A tab under the timeline: plain words, the chosen one in a soft glass capsule, white with
/// black text when focused (as the title page's season tabs).
struct OSDTabStyle: ButtonStyle {
    let chosen: Bool
    @Environment(\.isFocused) private var focused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .foregroundStyle(focused ? .black : .white.opacity(chosen ? 1 : 0.8))
            .background {
                if focused {
                    Capsule().fill(.white)
                } else {
                    GlassFill(shape: Capsule()).overlay(Capsule().stroke(.white.opacity(chosen ? 0.45 : 0), lineWidth: 1))
                }
            }
            .scaleEffect(focused ? 1.06 : 1)
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

/// The round Playback, Audio and Subtitles buttons and their menus. A view of their own so the
/// player's every tick of the clock doesn't rebuild an open menu, which made its focused choice
/// flash.
struct OSDTrackButtons: View {
    let model: PlayerModel
    let room: WatchRoom?
    let active: Bool
    let tab: OSDTab?
    var focus: FocusState<PlayerScreen.PlayerFocus?>.Binding
    let down: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // tvOS's own menus, as the system player's buttons open: they pop up above the
            // button with the choices ticked, and Back closes them.
            ForEach(OSDMenu.allCases, id: \.self) { m in
                Menu {
                    menuContent(m)
                } label: {
                    Image(systemName: m.icon).accessibilityLabel(m.title)
                }
                .menuStyle(.button)
                .buttonStyle(OSDIconStyle())
                .focused(focus, equals: .control(m))
                .disabled(!active || tab != nil)
                .onMoveCommand { if $0 == .down { down() } }
            }
        }
    }

    // MARK: Menus

    /// A menu's choices, as tvOS's own menu draws them (ticks, sections, submenus).
    @ViewBuilder private func menuContent(_ menu: OSDMenu) -> some View {
        switch menu {
        case .playback:
            Picker(L("player.zoom_mode"), selection: Binding(get: { model.zoomed }, set: { model.chooseZoom($0) })) {
                Text(L("player.zoom_normal")).tag(false)
                Text(L("player.zoom_fill")).tag(true)
            }
            .pickerStyle(.menu)
            // In a room the room sets the pace.
            if room == nil {
                Picker(L("player.speed"), selection: Binding(get: { model.speed }, set: { model.chooseSpeed($0) })) {
                    ForEach(PlayerOSD.speeds, id: \.self) { Text(L("player.speed_value", PlayerText.speedName($0))).tag($0) }
                }
                .pickerStyle(.menu)
            }
            Picker(L("player.quality"), selection: Binding(get: { model.maxKbps ?? 0 }, set: { model.chooseQuality($0 == 0 ? nil : $0) })) {
                Text(L("player.original")).tag(0)
                ForEach(model.qualities, id: \.self) { Text(qualityName($0)).tag($0) }
            }
            .pickerStyle(.menu)
            if model.versions.count > 1 {
                Picker(L("player.version"), selection: Binding(get: { model.fileId }, set: { model.chooseVersion($0) })) {
                    ForEach(model.versions) { Text($0.label).tag($0.fileId) }
                }
                .pickerStyle(.menu)
            }
            // Stats for nerds, as Android's Playback menu has: stays up over the picture until
            // turned off here.
            Toggle(L("player.playback_info"), isOn: Binding(get: { model.showsInfo }, set: { model.showsInfo = $0 }))
        case .audio:
            Picker(L("player.audio"), selection: Binding(get: { model.audioStream }, set: { model.chooseAudio($0) })) {
                ForEach(model.audioTracks) { Text(PlayerText.audioName($0)).tag($0.index) }
            }
            .pickerStyle(.inline)
        case .subtitles:
            Picker(L("player.subtitles"), selection: Binding(get: { model.subtitle?.id ?? "" }, set: { id in
                model.chooseSubtitle(model.subtitleTracks.first { $0.id == id })
            })) {
                Text(L("player.off")).tag("")
                ForEach(model.subtitleTracks) { Text(PlayerText.trackName($0)).tag($0.id) }
            }
            .pickerStyle(.inline)
            // Timing (arc-media-server#479): the menu's heading already says Subtitles.
            if model.subtitleTimingAdjustable {
                let offset = model.subtitleOffsetMs
                Section(PlayerText.timingName(offset)) {
                    Button(L("player.timing_show_earlier")) { model.shiftSubtitles(-SubtitleTiming.stepMs) }
                        .disabled(offset <= -SubtitleTiming.maxMs)
                    Button(L("player.timing_show_later")) { model.shiftSubtitles(SubtitleTiming.stepMs) }
                        .disabled(offset >= SubtitleTiming.maxMs)
                    Button(L("player.timing_reset")) { model.shiftSubtitles(nil) }
                        .disabled(offset == 0)
                }
            }
        }
    }
}

/// Playback Info ("stats for nerds"): a glass panel at the top right over the picture, read
/// again every second, until it's turned off in the Playback menu. It takes no focus.
struct PlaybackInfoPanel: View {
    let model: PlayerModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let rows = model.infoRows()
            VStack(alignment: .leading, spacing: 14) {
                Text(L("player.playback_info")).font(.callout.weight(.bold))
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            Text(row.label).foregroundStyle(.white.opacity(0.6))
                            Text(row.value).lineLimit(2)
                        }
                    }
                }
                .font(.caption2.weight(.medium).monospacedDigit())
            }
            .foregroundStyle(.white)
            .padding(28)
            .frame(width: 760, alignment: .leading)
            .arcGlassPanel(cornerRadius: 32)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}
