import ArcKit
import SwiftUI

extension CardStyle {
    var size: CGSize {
        switch self {
        case .poster: return CGSize(width: 220, height: 330)
        case .thumb: return CGSize(width: 400, height: 225)
        case .backdrop: return CGSize(width: 400, height: 300)
        }
    }
}

/// A title on a row, in its row's style. The tvOS card button gives the lift and shine on focus.
struct MediaCardView: View {
    let card: MediaCard
    let style: CardStyle
    var seasonPosters = false
    /// Where the row keeps which card has the focus (Home's backdrop follows it).
    var focus: FocusState<String?>.Binding
    let focusKey: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: action) {
                ZStack(alignment: .bottomLeading) {
                    ArtworkImage(path: card.art(style, seasonPosters: seasonPosters))
                        .frame(width: style.size.width, height: style.size.height)
                        .clipped()
                    if style == .backdrop, let logo = card.logo {
                        ArtworkImage(path: logo, contentMode: .fit)
                            .frame(width: style.size.width * 0.6, height: style.size.height * 0.3)
                            .padding(20)
                    }
                    if let progress = card.progress {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(.black.opacity(0.5))
                                Rectangle().fill(ArcColor.accent).frame(width: geo.size.width * progress)
                            }
                        }
                        .frame(height: 6)
                    }
                    if card.item.watched {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, ArcColor.accentStrong)
                            .padding(12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
                .frame(width: style.size.width, height: style.size.height)
            }
            .buttonStyle(.card)
            .focused(focus, equals: focusKey)
            if style != .poster {
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.item.isEpisode ? card.item.seriesTitle ?? card.item.title : card.item.title).font(.callout).lineLimit(1)
                    if let sub = subtitle { Text(sub).font(.caption).foregroundStyle(ArcColor.muted).lineLimit(1) }
                }
                .frame(width: style.size.width, alignment: .leading)
            }
        }
    }

    private var subtitle: String? {
        let item = card.item
        if let season = card.seasonNumber, card.newEpisodes > 0 { return L("card.new_episodes", season, card.newEpisodes) }
        if item.isEpisode, let s = item.seasonNumber, let e = item.episodeNumber { return L("card.episode", s, e, item.title) }
        return item.year.map(String.init)
    }
}
