import Foundation

// Hide Spoilers (`hide_spoilers` in /me/prefs): an episode the profile hasn't started keeps its
// still and description back, as the web's and arc-android's cards do.

extension Item {
    /// Whether this is an episode whose spoilers stay hidden: not watched and not started.
    public func spoilerHidden(_ hideSpoilers: Bool) -> Bool {
        hideSpoilers && isEpisode && userData?.played != true && resumeMs <= 0
    }
}

extension MediaCard {
    /// The same card keeping spoilers back: the show's background in place of the episode's
    /// still, else the still blurred (`blurred`).
    public func spoilerSafe(_ hideSpoilers: Bool) -> MediaCard {
        guard item.spoilerHidden(hideSpoilers), !showArt else { return self }
        var card = self
        if let show = item.images?.seriesBackdrop {
            card.thumb = show
        } else {
            card.blurred = card.thumb != nil && card.thumb == item.images?.primary
        }
        return card
    }
}
