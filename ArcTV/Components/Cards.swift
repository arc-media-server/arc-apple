import ArcKit
import SwiftUI

extension CardStyle {
    var size: CGSize {
        switch self {
        // Sized for a sofa: about four wide cards or six posters across the screen. Backdrops are
        // the web's squarer 4:3 card, four and a bit across (owner, 22 November).
        case .poster: return CGSize(width: 236, height: 354)
        case .thumb: return CGSize(width: 512, height: 288)
        case .backdrop: return CGSize(width: 360, height: 270)
        }
    }
}

/// How rounded artwork is, everywhere (tvOS 26's softer corners).
let cardCorner: CGFloat = 18

extension View {
    /// The words under a card move down as its artwork lifts on focus (tvOS's card grows about a
    /// tenth), so the two never touch, as tvOS's own lockups and Plex's posters do.
    func belowLiftedCard(_ lifted: Bool) -> some View {
        offset(y: lifted ? 22 : 0).animation(.easeOut(duration: 0.18), value: lifted)
    }
}

/// A title on a row or grid, in its row's style: rounded artwork that lifts on focus (tvOS's
/// card), how far through as a thin bar inside it, and its name with the year or time left under.
struct MediaCardView: View {
    @Environment(AppModel.self) private var app
    let card: MediaCard
    let style: CardStyle
    var seasonPosters = false
    /// The card is in Continue Watching or Up Next: its menu offers Remove from Continue Watching.
    var continueRow = false
    /// The card is an entry (this id) of Home's Queue row: its menu can move or remove it.
    var queueEntry: String?
    /// A film's length under its poster. Home and Recommended leave it out, so the year and
    /// edition ("2008 · IMAX") tell its versions apart (owner, 27 November).
    var showsLength = true
    /// Where the row keeps which card has the focus (Home's hero follows it).
    var focus: FocusState<String?>.Binding
    let focusKey: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: action) {
                ZStack(alignment: .bottomLeading) {
                    let art = card.spoilerSafe(app.hideSpoilers)
                    ArtworkImage(path: art.art(style, seasonPosters: seasonPosters))
                        .frame(width: style.size.width, height: style.size.height)
                        .blur(radius: style != .poster && art.blurred ? 24 : 0)
                        .clipped()
                    // As the web's (ArcArtwork.tsx): darker towards the bottom, the logo centred
                    // low on it, above the resume strip when there is one.
                    if style == .backdrop, let logo = card.logo {
                        LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                            .frame(height: style.size.height / 2)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                        ArtworkImage(path: logo, contentMode: .fit, placeholder: .clear)
                            .frame(maxWidth: style.size.width * 0.72, maxHeight: style.size.height * 0.26)
                            .shadow(color: .black.opacity(0.6), radius: 10, y: 2)
                            .padding(.bottom, card.progress == nil ? 22 : 46)
                            .frame(width: style.size.width, height: style.size.height, alignment: .bottom)
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
                    // A season's new episodes, a show's episodes still to watch, or a tick.
                    WatchBadge(item: card.item, newEpisodes: card.seasonNumber != nil ? card.newEpisodes : nil)
                }
                .frame(width: style.size.width, height: style.size.height)
                .clipShape(RoundedRectangle(cornerRadius: cardCorner, style: .continuous))
            }
            .buttonStyle(.card)
            .focused(focus, equals: focusKey)
            // VoiceOver (and the walk-through) know a card by its title.
            .accessibilityLabel(Text(name))
            .contextMenu { TitleActions(item: card.item, continueRow: continueRow, queueEntry: queueEntry) }
            // Names under the art, lined up with its left edge, as the other Arc apps.
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.callout.weight(.semibold)).lineLimit(1)
                if let sub = subtitle { Text(sub).font(.caption).foregroundStyle(ArcColor.muted).lineLimit(1) }
            }
            .frame(width: style.size.width, alignment: .leading)
            .belowLiftedCard(focus.wrappedValue == focusKey)
        }
    }

    private var name: String { card.name(style) }
    private var subtitle: String? { card.subtitle(style, showsLength: showsLength) }
}

/// The corner of a card's art, as every Arc app draws it: a show's (or a new season's) count of
/// episodes in a small white tab, else a white tick for something watched. White with black, as
/// Arc's chosen controls.
struct WatchBadge: View {
    let item: Item
    /// A Recently Added season's new episodes, in place of the show's own count.
    var newEpisodes: Int?

    var body: some View {
        Group {
            if let count = newEpisodes ?? (item.isSeries ? item.unwatchedCount : nil), count > 0 {
                Text(String(count))
                    .font(.system(size: 22, weight: .bold)).monospacedDigit()
                    .foregroundStyle(ArcColor.background)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ArcColor.foreground))
            } else if item.watched {
                Image(systemName: "checkmark")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(ArcColor.background)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(ArcColor.foreground))
                    .accessibilityLabel(Text(L("card.watched")))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
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

