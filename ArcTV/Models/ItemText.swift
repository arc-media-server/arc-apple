import ArcKit
import Foundation

// How a title's words read in every screen (cards, the player, Now Playing), on Apple TV and
// iPhone and iPad alike.

extension Item {
    /// The episode's number: "S1 · E4", or "Special 3"; nil when the show's order doesn't place it.
    var episodeCodeText: String? {
        switch episodeCode {
        case .numbered(let season, let number)?: return L("episode.code", season, number)
        case .special(let number)?: return L("episode.special", number)
        case nil: return nil
        }
    }

    /// Where the episode is the subject, its number then its name ("S1 · E4 · Pilot"); just its
    /// name when it has no number.
    var episodeLine: String { episodeCodeText.map { L("episode.with_title", $0, title) } ?? title }
}

extension Item {
    /// Its description, or a note in its place while it's an episode Hide Spoilers keeps back;
    /// nil when it has none.
    func overview(hidingSpoilers hide: Bool) -> String? {
        if spoilerHidden(hide) { return L("spoiler.hidden_description") }
        return overview.flatMap { $0.isEmpty ? nil : $0 }
    }
}

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

extension MediaCard {
    /// The name under the card: a show's, for an episode on a wide card.
    func name(_ style: CardStyle) -> String {
        item.isEpisode && style != .poster ? item.seriesTitle ?? item.title : item.title
    }

    /// The line under the name: the episode's number, the year and edition, or new episodes.
    func subtitle(_ style: CardStyle, showsLength: Bool = true) -> String? {
        // Recently Added's day of new episodes: a season says which (its count is the corner
        // badge), a whole show how many (arc-media-server, 12 and 13 November).
        if let season = seasonNumber { return season == 0 ? L("card.specials") : L("details.season", season) }
        if item.isSeries, newEpisodes > 0 {
            return newEpisodes == 1 ? L("card.new_episode") : L("card.new_episodes", newEpisodes)
        }
        var parts: [String] = []
        if let code = item.episodeCodeText {
            // Under the show's name, just the number ("S8 · E6"): the episode's name never shares it.
            parts.append(code)
        } else if item.isEpisode {
            // Outside the show's order there's no "S0 · E0": the episode's name, on a wide card.
            if style != .poster && progress == nil { parts.append(item.title) }
        } else if let yearAndEdition = item.yearAndEdition {
            parts.append(yearAndEdition)
        }
        // Posters say how long: a film's length, or a show's episodes' ("2011 · 25m").
        if style == .poster, !item.isEpisode, showsLength || item.isSeries, let m = item.runtimeMin, m > 0 { parts.append(runtimeText(m)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
