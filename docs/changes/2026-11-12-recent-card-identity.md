# Recently Added: a card's identity includes when it was added

The server now groups Recently Added episodes into 24-hour batches per show
(arc-media-server#446), so the same show or season can appear twice in the row: three episodes
of Season 2 on Monday and four more on Wednesday. Cards were identified by type, show and season
only, so those two cards had the same id, which confuses SwiftUI's ForEach (focus and artwork
can land on the wrong card).

`RecentCard` now reads `added_at` (already in the server's response) and a card's id includes
it. Older servers that don't send it give 0, the same id as before.

Checks: `swift test --package-path ArcKit` through the macOS build (new
testTheSameSeasonAddedOnTwoDaysIsTwoCardsWithTheirOwnIDs). No logging change: decoding only.
