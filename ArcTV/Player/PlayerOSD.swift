import ArcKit
import SwiftUI

/// The menus that open above the track buttons (top right of the controls).
enum OSDMenu: Hashable, CaseIterable {
    case subtitles, audio, playback

    var icon: String {
        switch self {
        case .subtitles: return "captions.bubble"
        case .audio: return "waveform"
        case .playback: return "slider.horizontal.3"
        }
    }

    var title: String {
        switch self {
        case .subtitles: return L("player.subtitles")
        case .audio: return L("player.audio")
        case .playback: return L("player.playback")
        }
    }
}

/// The cards that slide up from the bottom, chosen by the tab row under the timeline.
enum OSDTab: Hashable {
    case info, chapters, together

    var title: String {
        switch self {
        case .info: return L("player.info")
        case .chapters: return L("player.chapters")
        case .together: return L("together.title")
        }
    }
}

/// The player's on-screen controls, in the reference design's arrangement:
/// - the title at the bottom left, and the Subtitles, Audio and Playback buttons to its right,
///   each opening a menu above it;
/// - the timeline with the time played and the time left;
/// - the tab row under it (Info, Chapters, Watch Together). Down from the picture opens Info,
///   and a tab's card slides up from the bottom while the title and timeline step aside.
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
    let invite: () -> Void
    let leave: () -> Void
    let end: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(tab == nil ? 0.6 : 0.75)], startPoint: .top, endPoint: .bottom)
                .frame(height: tab == nil ? 420 : 640)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 22) {
                Spacer(minLength: 0)
                // The title and the timeline step aside while a card is up; the tabs stay.
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .bottom, spacing: 32) {
                        title
                        Spacer(minLength: 0)
                        trackButtons
                    }
                    timeline
                }
                .opacity(tab == nil ? 1 : 0)
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
        VStack(alignment: .leading, spacing: 4) {
            if model.item.isEpisode {
                Text(L("card.episode_code", model.item.seasonNumber ?? 0, model.item.episodeNumber ?? 0) + " · " + (model.item.seriesTitle ?? ""))
                    .font(.callout.weight(.medium)).foregroundStyle(.white.opacity(0.85))
            }
            Text(model.item.title).font(.system(size: 52, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
    }

    private var menus: [OSDMenu] {
        OSDMenu.allCases.filter { m in
            switch m {
            case .subtitles: return !model.subtitleTracks.isEmpty
            case .audio: return model.audioTracks.count > 1
            case .playback: return true
            }
        }
    }

    private var trackButtons: some View {
        HStack(spacing: 20) {
            ForEach(menus, id: \.self) { m in
                Button { openMenu(m) } label: {
                    Label(m.title, systemImage: m.icon)
                }
                .roundIconButton()
                .focused(focus, equals: .control(m))
                .disabled(!active || tab != nil || menu != nil)
            }
        }
    }

    private var timeline: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                let fraction = model.durationMs > 0 ? min(1, Double(model.positionMs) / Double(model.durationMs)) : 0
                ZStack(alignment: .leading) {
                    // The picture at this point, for a moment after moving through the timeline.
                    if let trick = model.trickplay, let at = model.seekedAt, Date().timeIntervalSince(at) < 3,
                       let spot = trick.thumbnail(at: model.positionMs) {
                        TrickplayThumb(sheet: spot.sheet, x: spot.x, y: spot.y, info: trick.info, chapter: model.chapter?.title)
                            .offset(x: min(max(0, geo.size.width * fraction - 180), geo.size.width - 360), y: -150)
                    }
                    Capsule().fill(.white.opacity(0.25)).frame(height: 8)
                    // Chapter marks.
                    ForEach(Array(model.chapters.enumerated()), id: \.offset) { _, c in
                        if model.durationMs > 0, c.startMs > 0 {
                            Rectangle().fill(.black.opacity(0.5)).frame(width: 3, height: 8)
                                .offset(x: geo.size.width * Double(c.startMs) / Double(model.durationMs))
                        }
                    }
                    Capsule().fill(.white).frame(width: geo.size.width * fraction, height: 8)
                    Circle().fill(.white).frame(width: 20, height: 20)
                        .shadow(color: .black.opacity(0.3), radius: 3)
                        .offset(x: geo.size.width * fraction - 10)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 20)
            HStack(spacing: 14) {
                Image(systemName: model.playing ? "pause.fill" : "play.fill")
                Text(PlayerOSD.time(model.positionMs)).monospacedDigit()
                Spacer()
                Text("-" + PlayerOSD.time(max(0, model.durationMs - model.positionMs))).monospacedDigit()
            }
            .font(.callout)
            .foregroundStyle(.white.opacity(0.85))
        }
    }

    // MARK: Tabs and cards

    private var tabs: [OSDTab] {
        var out: [OSDTab] = [.info]
        if !model.chapters.isEmpty { out.append(.chapters) }
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
        Group {
            switch tab {
            case .info: infoCard
            case .chapters: chaptersCard
            case .together: togetherCard
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
        .padding(30)
        .arcGlassPanel(cornerRadius: 32)
    }

    private var infoCard: some View {
        HStack(alignment: .top, spacing: 30) {
            ArtworkImage(path: model.item.images?.primary ?? model.item.images?.backdrop)
                .frame(width: 356, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 10) {
                Text(model.item.title).font(.title3.weight(.semibold)).lineLimit(1)
                if let overview = model.item.overview, !overview.isEmpty {
                    Text(overview).font(.callout).foregroundStyle(.white.opacity(0.85)).lineLimit(3)
                }
                let quality = Quality.summary(Quality.file(of: model.item))
                Text([quality, model.methodName, model.engineName].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption.weight(.medium)).foregroundStyle(ArcColor.muted).lineLimit(1)
            }
        }
    }

    private var chaptersCard: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 24) {
                ForEach(Array(model.chapters.enumerated()), id: \.offset) { i, c in
                    Button { jump(c) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text((c.title?.isEmpty == false ? c.title : nil) ?? L("player.chapter", i + 1))
                                .font(.callout.weight(.semibold)).lineLimit(1)
                            Text(PlayerOSD.time(c.startMs)).font(.caption).foregroundStyle(ArcColor.muted)
                        }
                        .frame(width: 260, alignment: .leading)
                    }
                    .buttonStyle(.card)
                    .focused(focus, equals: .chapter(i))
                }
            }
            .padding(.vertical, 12)
        }
        .scrollClipDisabled()
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

    private func menuPanel(_ menu: OSDMenu) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 10) {
                switch menu {
                case .subtitles:
                    option(L("player.off"), selected: model.subtitle == nil, key: "s:off") { model.chooseSubtitle(nil) }
                    ForEach(model.subtitleTracks) { t in
                        option(PlayerOSD.trackName(t), selected: model.subtitle?.id == t.id, key: "s:" + t.id) { model.chooseSubtitle(t) }
                    }
                case .audio:
                    ForEach(model.audioTracks) { a in
                        option(PlayerOSD.audioName(a), selected: model.audioStream == a.index, key: "a:\(a.index)") { model.chooseAudio(a.index) }
                    }
                case .playback:
                    Text(L("player.quality")).font(.caption.weight(.semibold)).foregroundStyle(ArcColor.muted)
                    option(L("player.original"), selected: model.maxKbps == nil, key: "q:original") { model.chooseQuality(nil) }
                    ForEach(model.qualities, id: \.self) { kbps in
                        option(qualityName(kbps), selected: model.maxKbps == kbps, key: "q:\(kbps)") { model.chooseQuality(kbps) }
                    }
                    if model.versions.count > 1 {
                        Text(L("player.version")).font(.caption.weight(.semibold)).foregroundStyle(ArcColor.muted).padding(.top, 12)
                        ForEach(model.versions) { v in
                            option(v.label, selected: model.fileId == v.fileId, key: "v:\(v.fileId)") { model.chooseVersion(v.fileId) }
                        }
                    }
                }
            }
            .padding(24)
        }
        .frame(width: 560)
        .frame(maxHeight: 560)
        .fixedSize(horizontal: false, vertical: true)
        .arcGlassPanel(cornerRadius: 32)
        .focusSection()
        // Above the buttons, at the right: the controls' bottom margin, the timeline and the
        // tab row stay visible under it.
        .padding(.trailing, 90)
        .padding(.bottom, 290)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    private func option(_ title: String, selected: Bool, key: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: "checkmark").font(.callout.weight(.semibold)).opacity(selected ? 1 : 0)
                Text(title).lineLimit(1)
                Spacer(minLength: 0)
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
            .foregroundStyle(focused ? .black : .white.opacity(chosen ? 1 : 0.7))
            .background {
                if focused {
                    Capsule().fill(.white)
                } else if chosen {
                    Capsule().fill(.ultraThinMaterial).overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 1))
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
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .foregroundStyle(focused ? .black : .white)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(focused ? .white : .clear))
            .scaleEffect(focused ? 1.02 : 1)
            .animation(.easeOut(duration: 0.12), value: focused)
    }
}
