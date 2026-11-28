import ArcKit
import SwiftUI

/// A title on a row or grid: rounded artwork with how far through, the corner badge, and its name
/// with the year or episode number under it (the same words as the TV's cards). A tap opens it
/// (or plays an episode part-way through, as Plex's Continue Watching); touching and holding
/// shows its actions, as iOS's context menus.
struct MobileCard: View {
    @Environment(AppModel.self) private var app
    @Environment(Browse.self) private var browse
    @Environment(\.openRoute) private var openRoute
    let card: MediaCard
    let style: CardStyle
    var seasonPosters = false
    /// Continue Watching or Up Next: the menu offers Remove from Continue Watching.
    var continueRow = false
    /// An entry (this id) of Home's Queue row: it plays on from there.
    var queueEntry: String?
    var showsLength = true
    /// The artwork's width; nil fills the space it's given (a grid's column).
    var width: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: open) {
                artwork
            }
            .buttonStyle(.plain)
            .contextMenu { TitleActions(item: card.item, continueRow: continueRow, queueEntry: queueEntry) }
            .accessibilityLabel(Text(card.name(style)))
            VStack(alignment: .leading, spacing: 1) {
                Text(card.name(style)).font(.footnote.weight(.semibold)).lineLimit(1)
                if let sub = card.subtitle(style, showsLength: showsLength) {
                    Text(sub).font(.caption).foregroundStyle(ArcColor.muted).lineLimit(1)
                }
            }
            .accessibilityHidden(true)
        }
        .frame(width: width)
    }

    private var aspect: CGFloat {
        switch style {
        case .poster: return 2.0 / 3.0
        case .thumb: return 16.0 / 9.0
        case .backdrop: return 4.0 / 3.0
        }
    }

    private var artwork: some View {
        let art = card.spoilerSafe(app.hideSpoilers)
        return Color.clear
            .aspectRatio(aspect, contentMode: .fit)
            .overlay {
                ArtworkImage(path: art.art(style, seasonPosters: seasonPosters))
                    .blur(radius: style != .poster && art.blurred ? 14 : 0)
            }
            .overlay(alignment: .bottom) {
                if style != .poster, let logo = card.logo, card.showArt || style == .backdrop {
                    ArtworkImage(path: logo, contentMode: .fit, placeholder: .clear)
                        .frame(maxHeight: 36)
                        .padding(.horizontal, 24)
                        .padding(.bottom, card.progress == nil ? 12 : 22)
                        .shadow(color: .black.opacity(0.6), radius: 6, y: 1)
                }
            }
            .overlay(alignment: .bottom) {
                if let progress = card.progress { MobileProgressBar(fraction: progress).padding(8) }
            }
            .overlay(alignment: .topTrailing) {
                MobileWatchBadge(item: card.item, newEpisodes: card.seasonNumber != nil ? card.newEpisodes : nil)
            }
            .clipShape(RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous))
    }

    private func open() {
        let item = card.item
        if let queueEntry {
            browse.play(PlayRequest(item: item, startMs: item.resumeMs, queueEntry: queueEntry))
        } else if item.isEpisode && card.progress != nil {
            browse.play(PlayRequest(item: item, startMs: item.resumeMs))
        } else {
            openRoute(.item(item))
        }
    }
}

/// How far through, as a thin white bar on a dark track.
struct MobileProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.55))
                Capsule().fill(ArcColor.foreground).frame(width: g.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 4)
    }
}

/// The corner of a card's art, as every Arc app draws it: a show's (or a new season's) count of
/// episodes in a small white tab, else a white tick for something watched.
struct MobileWatchBadge: View {
    let item: Item
    var newEpisodes: Int?

    var body: some View {
        Group {
            if let count = newEpisodes ?? (item.isSeries ? item.unwatchedCount : nil), count > 0 {
                Text(String(count))
                    .font(.caption2.weight(.bold)).monospacedDigit()
                    .foregroundStyle(ArcColor.background)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(ArcColor.foreground))
            } else if item.watched {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(ArcColor.background)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(ArcColor.foreground))
                    .accessibilityLabel(Text(L("card.watched")))
            }
        }
        .padding(6)
    }
}

/// A titled row of cards that scrolls sideways, snapping to the cards, as Apple's TV app's rows.
struct MobileRow: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let title: String
    let cards: [MediaCard]
    let style: CardStyle
    var seasonPosters = false
    var continueRow = false
    var queueRow = false
    var showsLength = true

    var body: some View {
        let wide = sizeClass == .regular
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.bold))
                .padding(.horizontal, Metrics.margin(wide))
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: wide ? 16 : 12) {
                    ForEach(cards) { card in
                        MobileCard(card: card, style: style, seasonPosters: seasonPosters, continueRow: continueRow,
                                   queueEntry: queueRow ? card.id : nil, showsLength: showsLength,
                                   width: Metrics.card(style, wide: wide).width)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, Metrics.margin(wide), for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
    }
}

/// Titles in a grid that fills the width: a library, a collection, a playlist, a search's results.
struct MobileGrid: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let cards: [MediaCard]
    var style: CardStyle = .poster
    /// Called as the last cards come on screen, to load the next page.
    var onEnd: (() -> Void)? = nil

    var body: some View {
        let wide = sizeClass == .regular
        let minimum = style == .poster ? Metrics.gridPoster(wide) : Metrics.card(style, wide: wide).width * 0.8
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum), spacing: wide ? 16 : 12, alignment: .top)], spacing: 20) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                MobileCard(card: card, style: style)
                    .onAppear { if index >= cards.count - 8 { onEnd?() } }
            }
        }
        .padding(.horizontal, Metrics.margin(wide))
    }
}
