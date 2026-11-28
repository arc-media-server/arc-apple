import ArcKit
import SwiftUI

/// Sizes for iPhone and iPad (colours stay in Theme.swift). iPad's regular width gets larger
/// cards, about as many across as Plex's and the TV app's on the larger screen.
enum Metrics {
    /// The page's side margin, as iOS's own lists and Apple's TV app.
    static func margin(_ wide: Bool) -> CGFloat { wide ? 32 : 16 }

    /// A card's artwork size in a row.
    static func card(_ style: CardStyle, wide: Bool) -> CGSize {
        switch style {
        case .poster: return wide ? CGSize(width: 150, height: 225) : CGSize(width: 112, height: 168)
        case .thumb: return wide ? CGSize(width: 320, height: 180) : CGSize(width: 248, height: 140)
        case .backdrop: return wide ? CGSize(width: 240, height: 180) : CGSize(width: 184, height: 138)
        }
    }

    /// The narrowest a poster gets in a library's grid.
    static func gridPoster(_ wide: Bool) -> CGFloat { wide ? 140 : 104 }

    /// How rounded artwork is (iOS's smaller corners than the TV's).
    static let corner: CGFloat = 10
}
