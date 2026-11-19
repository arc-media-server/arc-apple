import ArcKit
import SwiftUI

extension CardStyle {
    var size: CGSize {
        switch self {
        // Sized for a sofa: about four wide cards or six posters across the screen.
        case .poster: return CGSize(width: 236, height: 354)
        case .thumb: return CGSize(width: 512, height: 288)
        case .backdrop: return CGSize(width: 512, height: 384)
        }
    }
}

/// How rounded artwork is, everywhere (tvOS 26's softer corners).
let cardCorner: CGFloat = 18

extension MediaCard {
    /// Minutes left of a part-watched title.
    var minutesLeft: Int? {
        guard progress != nil else { return nil }
        return max(1, Int((item.durationMs - item.resumeMs) / 60_000))
    }
}

/// A length as the cards and title pages write it: "25m", "1h", "2h 25m".
func runtimeText(_ minutes: Int) -> String {
    if minutes < 60 { return L("card.minutes_short", minutes) }
    return minutes % 60 == 0 ? L("details.hours", minutes / 60) : L("details.hours_minutes", minutes / 60, minutes % 60)
}

/// A title on a row or grid, in its row's style: rounded artwork that lifts on focus (tvOS's
/// card), how far through as a thin bar inside it, and its name with the year or time left under.
struct MediaCardView: View {
    let card: MediaCard
    let style: CardStyle
    var seasonPosters = false
    /// The card is in Continue Watching or Up Next: its menu offers Remove from Continue Watching.
    var continueRow = false
    /// Where the row keeps which card has the focus (Home's hero follows it).
    var focus: FocusState<String?>.Binding
    let focusKey: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            Button(action: action) {
                ZStack(alignment: .bottomLeading) {
                    ArtworkImage(path: card.art(style, seasonPosters: seasonPosters))
                        .frame(width: style.size.width, height: style.size.height)
                        .clipped()
                    if style == .backdrop, let logo = card.logo {
                        ArtworkImage(path: logo, contentMode: .fit, placeholder: .clear)
                            .frame(width: style.size.width * 0.6, height: style.size.height * 0.3)
                            .padding(20)
                    }
                    // The show's own picture carries its logo, as Continue Watching's do.
                    if style == .thumb, card.showArt, card.progress == nil, let logo = card.logo {
                        ArtworkImage(path: logo, contentMode: .fit, placeholder: .clear)
                            .frame(width: style.size.width * 0.55, height: style.size.height * 0.3)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                    }
                    if let progress = card.progress {
                        if style == .poster {
                            ProgressBar(fraction: progress).padding(12)
                        } else {
                            // Wide cards carry a resume strip on the art: play, how far, time left.
                            if style == .thumb, let logo = card.logo {
                                ArtworkImage(path: logo, contentMode: .fit, placeholder: .clear)
                                    .frame(width: style.size.width * 0.55, height: style.size.height * 0.3)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                                    .padding(.horizontal, 20)
                            }
                            ResumeStrip(fraction: progress, minutesLeft: card.minutesLeft)
                        }
                    }
                    // A show's episodes still to watch, in a tab at the poster's top right.
                    if let left = card.item.unwatchedCount, left > 0, card.item.isSeries, style == .poster {
                        Text(String(left))
                            .font(.caption.weight(.bold)).monospacedDigit()
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(UnevenRoundedRectangle(bottomLeadingRadius: 12, style: .continuous).fill(.black.opacity(0.8)))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                    if card.item.watched {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.black, .white)
                            .padding(10)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
                .frame(width: style.size.width, height: style.size.height)
                .clipShape(RoundedRectangle(cornerRadius: cardCorner, style: .continuous))
            }
            .buttonStyle(.card)
            .focused(focus, equals: focusKey)
            // VoiceOver (and the walk-through) know a card by its title.
            .accessibilityLabel(Text(name))
            .contextMenu { TitleActions(item: card.item, continueRow: continueRow) }
            // Names centred under the art.
            VStack(alignment: .center, spacing: 2) {
                Text(name)
                    .font(.callout.weight(.semibold)).lineLimit(1)
                if let sub = subtitle { Text(sub).font(.caption).foregroundStyle(ArcColor.muted).lineLimit(1) }
            }
            .frame(width: style.size.width, alignment: .center)
        }
    }

    private var name: String {
        card.item.isEpisode && style != .poster ? card.item.seriesTitle ?? card.item.title : card.item.title
    }

    private var subtitle: String? {
        let item = card.item
        if let season = card.seasonNumber, card.newEpisodes > 0 { return L("card.new_episodes", season, card.newEpisodes) }
        var parts: [String] = []
        if item.hasEpisodeCode, let s = item.seasonNumber, let e = item.episodeNumber {
            // A part-watched episode's card is short: S8 · E6 (the strip has the time).
            parts.append(style == .poster || card.progress != nil ? L("card.episode_code", s, e) : L("card.episode", s, e, item.title))
        } else if item.isEpisode {
            // Outside the show's order there's no "S0 · E0": the episode's name, on a wide card.
            if style != .poster && card.progress == nil { parts.append(item.title) }
        } else if let year = item.year {
            parts.append(String(year))
        }
        // Posters say how long: a film's length, or a show's episodes' ("2011 · 25m").
        if style == .poster, !item.isEpisode, let m = item.runtimeMin, m > 0 { parts.append(runtimeText(m)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// A wide card's resume strip along the bottom of the art: a play mark, how far through and the
/// minutes left, over a soft shade so it reads on any picture.
struct ResumeStrip: View {
    let fraction: Double
    let minutesLeft: Int?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "play.fill").font(.caption2)
            ProgressBar(fraction: fraction).frame(width: 70)
            if let minutesLeft { Text(L("card.minutes_short", minutesLeft)).font(.caption2.weight(.semibold)) }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
    }
}

/// The Play button's label. Not started: "Play" for a film, "Start watching · S1, E1" for a
/// season's first episode, "Play S21 E8" for any other. Part watched: a bar of how far through
/// with what's left, after the episode's number ("S5 E12 · 43m") or alone for a film ("1h 2m").
struct PlayLabel: View {
    let item: Item
    let episode: Bool

    var body: some View {
        let resume = item.resumeMs
        let duration = item.durationMs
        let season = item.seasonNumber ?? 0, number = item.episodeNumber ?? 0
        HStack(spacing: 14) {
            Image(systemName: "play.fill")
            if resume > 0, duration > resume {
                let left = Int((duration - resume + 59_999) / 60_000)
                // The bar follows the label's colour, so it shows on the white of focus too.
                ZStack(alignment: .leading) {
                    Capsule().fill(.secondary).frame(width: 70, height: 6)
                    Capsule().fill(.primary).frame(width: 70 * CGFloat(Double(resume) / Double(duration)), height: 6)
                }
                Text(episode && item.hasEpisodeCode ? L("details.resume_episode_left", season, number, runtimeText(left)) : runtimeText(left))
            } else if episode && item.hasEpisodeCode {
                Text(number == 1 ? L("details.start_watching", season, number) : L("details.play_episode", season, number))
            } else {
                Text(L("details.play"))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A content rating (PG-13, TV-14) in an outlined box, as the title pages and the hero show it.
struct OutlinedBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.85), lineWidth: 1.5))
    }
}

/// A file's quality as the title page shows it: a capsule, filled white for the resolution
/// ("4K", "1080p") and outlined for the rest, its parts split by a thin line ("DV | HDR10").
struct QualityCapsule: View {
    let capsule: Quality.Capsule

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(capsule.parts.enumerated()), id: \.offset) { index, part in
                if index > 0 { Rectangle().fill(.white.opacity(0.6)).frame(width: 1.5).padding(.vertical, 3) }
                Text(part).padding(.horizontal, 8)
            }
        }
        .font(.caption2.weight(.bold))
        .padding(.horizontal, 2).padding(.vertical, 2)
        .foregroundStyle(capsule.filled ? Color.black : Color.white)
        .background(Capsule().fill(.white.opacity(capsule.filled ? 0.9 : 0)))
        .overlay(Capsule().stroke(.white.opacity(capsule.filled ? 0 : 0.75), lineWidth: 1.5))
        .fixedSize()
    }
}

/// How far through: a thin rounded bar inset at the bottom of the artwork.
struct ProgressBar: View {
    let fraction: Double
    /// White on art; black on a white button.
    var color: Color = .white

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.3))
                Capsule().fill(color).frame(width: max(6, geo.size.width * fraction))
            }
        }
        .frame(height: 5)
    }
}

/// A title's actions, from holding Select on its card (Plex's context menu) and on its page:
/// play, watched or not, the Watchlist, an episode's show, and taking a title out of Continue
/// Watching.
struct TitleActions: View {
    @Environment(AppModel.self) private var app
    @Environment(Browse.self) private var browse
    @Environment(\.openRoute) private var openRoute
    let item: Item
    var onPage = false
    /// Opened from a card in Continue Watching or Up Next.
    var continueRow = false

    var body: some View {
        if !onPage && item.playable {
            Button { browse.play(PlayRequest(item: item, startMs: item.resumeMs)) } label: {
                Label(item.resumeMs > 0 ? L("details.resume") : L("details.play"), systemImage: "play.fill")
            }
            if item.resumeMs > 0 {
                Button { browse.play(PlayRequest(item: item, startMs: 0)) } label: {
                    Label(L("details.from_beginning"), systemImage: "arrow.counterclockwise")
                }
            }
        }
        if item.playable || item.isSeries {
            Button { act("watched") { try await $0.setPlayed(item.id, !item.watched) } } label: {
                Label(item.watched ? L("actions.mark_unwatched") : L("actions.mark_watched"),
                      systemImage: item.watched ? (onPage ? "checkmark.circle.fill" : "eye.slash") : "checkmark.circle")
            }
        }
        // Out of Continue Watching and Up Next without marking it watched (an episode: its whole
        // show, until something of it plays again), as the web's card menu does.
        if continueRow && !onPage {
            Button { act("remove from continue") { try await $0.removeFromContinue(item.id) } } label: {
                Label(L("actions.remove_from_continue"), systemImage: "xmark.circle")
            }
        }
        if item.kind == "movie" || item.isSeries {
            let on = item.userData?.watchlisted == true
            Button { act("watchlist") { try await $0.setWatchlisted(item.id, !on) } } label: {
                Label(on ? L("actions.watchlist_remove") : L("actions.watchlist_add"), systemImage: on ? "bookmark.slash" : "bookmark")
            }
        }
        // What a playlist can hold: films, episodes and whole shows.
        if item.kind == "movie" || item.isEpisode || item.isSeries {
            Button { browse.addingToPlaylist = item } label: {
                Label(L("actions.add_to_playlist"), systemImage: "text.badge.plus")
            }
        }
        // The profile's own stars, on the title's page (as the web's StarRating).
        if onPage && (item.kind == "movie" || item.isEpisode || item.isSeries) {
            rate
        }
        if item.kind == "movie" || item.isEpisode {
            Button { browse.together.inviting = .init(itemId: item.id, title: item.title) } label: {
                Label(L("together.menu"), systemImage: "person.2")
            }
        }
        if !onPage, item.isEpisode, let show = item.parentId {
            Button { openRoute(.item(Item(id: show, kind: "series", title: item.seriesTitle ?? item.title))) } label: {
                Label(L("actions.go_to_show"), systemImage: "tv")
            }
        }
    }

    /// Rate…: five stars in halves, best first, the current one ticked, and Clear Rating.
    private var rate: some View {
        let current = item.userData?.rating ?? 0
        return Menu {
            Section(L("rating.title")) {
                ForEach(StarRating.choices, id: \.self) { r in
                    let text = L("rating.choice", StarRating.stars(r) ?? "", StarRating.outOfFive(r))
                    Button { setRating(r) } label: {
                        if r == current { Label(text, systemImage: "checkmark") } else { Text(text) }
                    }
                }
                if current > 0 {
                    Button { setRating(0) } label: { Label(L("rating.clear"), systemImage: "xmark") }
                }
            }
        } label: {
            Label(StarRating.stars(current).map { L("rating.title") + " " + $0 } ?? L("actions.rate"),
                  systemImage: current > 0 ? "star.fill" : "star")
        }
    }

    private func setRating(_ rating: Int) {
        act(rating == 0 ? "rating cleared" : "rating") { try await $0.setRating(item.id, rating) }
    }

    private func act(_ what: String, _ call: @escaping (ArcAPI) async throws -> Void) {
        guard let api = app.api else { return }
        Task {
            do {
                try await call(api)
                ArcLogApp.debug("title action done: \(what)")
                browse.changed()
            } catch let error as APIError where error.status == 401 {
                app.tokenRefused()
            } catch {
                ArcLogApp.warn("title action \(what) failed: \(type(of: error))")
            }
        }
    }
}
