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
/// - at the bottom left the title (for an episode, "S2, E4 • its name" over the show's name), and
///   to its right three small round buttons, Playback, Audio and Subtitles, each opening a menu
///   above it;
/// - the timeline, split at the chapters, with the time played under its marker and the time
///   left at the right;
/// - the tab row under it (Info, Chapters, Cast, Episodes, and Watch Together in a room). Down
///   from the picture opens Info; a tab's card slides up while the title and timeline step aside.
/// The screen keeps the state (which menu, which tab, the focus); this view only draws it.
struct PlayerOSD: View {
    let model: PlayerModel
    let room: WatchRoom?
    /// The menu open above its button, if any.
    let menu: OSDMenu?
    /// The card open from the tab row, if any.
    let tab: OSDTab?
    /// Whether the buttons and tabs take the focus (after Up or Down from the picture).
    let active: Bool
    var focus: FocusState<PlayerScreen.PlayerFocus?>.Binding
    let openMenu: (OSDMenu) -> Void
    let jump: (Chapter) -> Void
    /// Plays another episode (the Episodes card, the Info card's Previous).
    let play: (Item) -> Void
    let restart: () -> Void
    let invite: () -> Void
    let leave: () -> Void
    let end: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(tab == nil ? 0.6 : 0.7)], startPoint: .top, endPoint: .bottom)
                .frame(height: tab == nil ? 440 : 600)
                .frame(maxHeight: .infinity, alignment: .bottom)
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
                            trackButtons
                        }
                        timeline
                    }
                    .transition(.opacity)
                }
                tabRow
                if let tab {
                    card(tab)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 90)
            .padding(.bottom, 60)
            .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.45), value: tab)
            if let menu {
                menuPanel(menu)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottomTrailing)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: menu)
    }

    // MARK: Title, buttons, timeline

    private var title: some View {
        let item = model.item
        return VStack(alignment: .leading, spacing: 6) {
            if item.isEpisode {
                Text(L("player.episode_line", item.seasonNumber ?? 0, item.episodeNumber ?? 0, item.title))
                    .font(.callout.weight(.medium)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
            }
            Text(item.isEpisode ? (item.seriesTitle ?? item.title) : item.title)
                .font(.system(size: 52, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
    }

    private var trackButtons: some View {
        HStack(spacing: 16) {
            ForEach(OSDMenu.allCases, id: \.self) { m in
                Button { openMenu(m) } label: {
                    Image(systemName: m.icon).accessibilityLabel(m.title)
                }
                .buttonStyle(OSDIconStyle())
                .focused(focus, equals: .control(m))
                .disabled(!active || tab != nil || menu != nil)
            }
        }
    }

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
            let gap: CGFloat = pieces.count > 1 ? 6 : 0
            let usable = width - gap * CGFloat(pieces.count - 1)
            let total = Double(max(1, pieces.last?.end ?? 1))
            let widths = pieces.map { max(2, usable * CGFloat(Double($0.end - $0.start) / total)) }
            let x = markerX(widths: widths, gap: gap, pieces: pieces)
            ZStack(alignment: .topLeading) {
                HStack(spacing: gap) {
                    ForEach(Array(pieces.enumerated()), id: \.offset) { i, piece in
                        let done = min(1, max(0, Double(model.positionMs - piece.start) / Double(max(1, piece.end - piece.start))))
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.3))
                            Capsule().fill(.white).frame(width: widths[i] * done)
                        }
                        .frame(width: widths[i], height: 6)
                    }
                }
                .position(x: width / 2, y: 11)
                RoundedRectangle(cornerRadius: 2.5).fill(.white)
                    .frame(width: 5, height: 22)
                    .shadow(color: .black.opacity(0.35), radius: 3)
                    .position(x: x, y: 11)
                // The time played, under the marker, and the time left at the end.
                HStack(spacing: 10) {
                    Text(PlayerOSD.time(model.positionMs)).monospacedDigit()
                    Image(systemName: model.playing ? "pause.circle.fill" : "play.circle.fill")
                }
                .font(.callout.weight(.semibold))
                .fixedSize()
                .position(x: min(max(x, 60), width - 260), y: 48)
                Text("-" + PlayerOSD.time(max(0, model.durationMs - model.positionMs)))
                    .font(.callout.weight(.semibold)).monospacedDigit()
                    .frame(width: width, alignment: .trailing)
                    .position(x: width / 2, y: 48)
                // The picture at this point, for a moment after moving through the timeline.
                if let trick = model.trickplay, let at = model.seekedAt, Date().timeIntervalSince(at) < 3,
                   let spot = trick.thumbnail(at: model.positionMs) {
                    TrickplayThumb(sheet: spot.sheet, x: spot.x, y: spot.y, info: trick.info, chapter: model.chapter?.title)
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
            if model.positionMs < piece.end || i == pieces.count - 1 {
                let done = min(1, max(0, Double(model.positionMs - piece.start) / Double(max(1, piece.end - piece.start))))
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
                    .disabled(!active || menu != nil)
            }
        }
        .focusSection()
    }

    @ViewBuilder private func card(_ tab: OSDTab) -> some View {
        switch tab {
        case .info: panel { infoCard }
        case .chapters: chaptersCard
        case .cast: castCard
        case .episodes: panel { episodesCard }
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
        if item.isEpisode {
            parts.append(L("card.episode_code", item.seasonNumber ?? 0, item.episodeNumber ?? 0))
        }
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
                                Text(PlayerOSD.time(c.startMs)).font(.caption).monospacedDigit()
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
                                        Text(L("card.episode_code", episode.seasonNumber ?? 0, episode.episodeNumber ?? 0))
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

    // MARK: Menus

    static let speeds: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]

    private func menuPanel(_ menu: OSDMenu) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(menu.title).font(.headline).padding(.horizontal, 20)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 4) {
                    switch menu {
                    case .playback:
                        row(L("player.zoom_mode"), value: L(model.zoomed ? "player.zoom_fill" : "player.zoom_normal"), key: "p:zoom") {
                            model.chooseZoom(!model.zoomed)
                        }
                        // In a room the room sets the pace.
                        if room == nil {
                            row(L("player.speed"), value: L("player.speed_value", PlayerOSD.speedName(model.speed)), key: "p:speed") {
                                let speeds = PlayerOSD.speeds
                                let i = speeds.firstIndex(of: model.speed) ?? 2
                                model.chooseSpeed(speeds[(i + 1) % speeds.count])
                            }
                        }
                        heading(L("player.quality"))
                        option(L("player.original"), selected: model.maxKbps == nil, key: "q:original") { model.chooseQuality(nil) }
                        ForEach(model.qualities, id: \.self) { kbps in
                            option(qualityName(kbps), selected: model.maxKbps == kbps, key: "q:\(kbps)") { model.chooseQuality(kbps) }
                        }
                        if model.versions.count > 1 {
                            heading(L("player.version"))
                            ForEach(model.versions) { v in
                                option(v.label, selected: model.fileId == v.fileId, key: "v:\(v.fileId)") { model.chooseVersion(v.fileId) }
                            }
                        }
                    case .audio:
                        ForEach(model.audioTracks) { a in
                            option(PlayerOSD.audioName(a), selected: model.audioStream == a.index, key: "a:\(a.index)") { model.chooseAudio(a.index) }
                        }
                    case .subtitles:
                        option(L("player.off"), selected: model.subtitle == nil, key: "s:off") { model.chooseSubtitle(nil) }
                        ForEach(model.subtitleTracks) { t in
                            option(PlayerOSD.trackName(t), selected: model.subtitle?.id == t.id, key: "s:" + t.id) { model.chooseSubtitle(t) }
                        }
                    }
                }
                .padding(.horizontal, 6)
            }
            .scrollClipDisabled()
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 8)
        .frame(width: 520)
        .frame(maxHeight: 520)
        .fixedSize(horizontal: false, vertical: true)
        .arcGlassPanel(cornerRadius: 28)
        .focusSection()
        // Just above the round buttons, at the right; the timeline and tabs stay in view.
        .padding(.trailing, 90)
        .padding(.bottom, 300)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
            .padding(.horizontal, 20).padding(.top, 10)
    }

    /// A choice: its name, ticked at the right when chosen.
    private func option(_ title: String, selected: Bool, key: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Text(title).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "checkmark").font(.callout.weight(.semibold)).opacity(selected ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(OSDRowStyle())
        .focused(focus, equals: .option(key))
    }

    /// A setting: its name, and its value at the right; Select moves to the next value.
    private func row(_ title: String, value: String, key: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title).lineLimit(1)
                Spacer(minLength: 0)
                Text(value).opacity(0.7)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).opacity(0.7)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(OSDRowStyle())
        .focused(focus, equals: .option(key))
    }

    // MARK: Words

    static func time(_ ms: Int64) -> String {
        let s = Int(ms / 1000)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    static func speedName(_ speed: Float) -> String {
        speed.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// "24 Oct 2026", from the server's yyyy-MM-dd.
    static func day(_ iso: String) -> String? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: iso) else { return nil }
        let out = DateFormatter()
        out.setLocalizedDateFormatFromTemplate("d MMM yyyy")
        return out.string(from: d)
    }

    static func trackName(_ t: SubtitleTrack) -> String {
        var parts = [languageName(t.language) ?? t.title ?? L("player.unknown_language")]
        if let title = t.title, !title.isEmpty, parts.first != title { parts.append(title) }
        if t.forced { parts.append(L("player.forced")) }
        if t.hearingImpaired { parts.append(L("player.sdh")) }
        return parts.joined(separator: " · ")
    }

    static func audioName(_ a: AudioTrack) -> String {
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

    private static func languageName(_ code: String?) -> String? {
        guard let code, !code.isEmpty, code != "und" else { return nil }
        return Locale.current.localizedString(forLanguageCode: code) ?? code
    }
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
                    Circle().fill(.ultraThinMaterial).overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
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
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.white.opacity(focused ? 0.22 : 0)))
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(focused ? 0.6 : 0.2), lineWidth: 1))
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
                    Capsule().fill(.ultraThinMaterial).overlay(Capsule().stroke(.white.opacity(chosen ? 0.45 : 0.15), lineWidth: 1))
                }
            }
            .scaleEffect(focused ? 1.06 : 1)
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

/// A row in a player menu: full width, white with black text when focused.
struct OSDRowStyle: ButtonStyle {
    @Environment(\.isFocused) private var focused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .foregroundStyle(focused ? .black : .white)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(focused ? .white : .clear))
            .scaleEffect(focused ? 1.02 : 1)
            .animation(.easeOut(duration: 0.12), value: focused)
    }
}
