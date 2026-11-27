# Apple TV: the title page and episodes (the owner's 27 November list)

Part of the owner's 27 November list for the Apple TV app, with arc-android as the reference. It
builds on the Home, Library and cards PR (the episode cards use its corner badge, and the page its
year and edition).

## What changed

- **The title page** sits lower and further left:
  - The words start at tvOS's own margin, 80 px from the left. Before, they started at 160 px.
  - A film's buttons sit about 80 px above the bottom, and its cast comes up closer under them.
  - A show's buttons sit just above its season tabs, which peek in at the bottom. Before, the
    tops of the episodes peeked in.
- **A show's page flows as Android's:**
  - Down from Play goes to the season tabs, on the season showing.
  - The tabs and episodes land at the foot of the screen, with the page above them and the
    artwork dimmed behind them, with the descriptions in full every time. tvOS's own scroll for
    the focus used to win over Arc's and cut them off.
  - Up from the tabs brings the whole page back.
  - Before, the artwork and words slid away and the show's logo appeared at the top, as Apple's
    TV app does.
- **Episodes:**
  - Each card is 400 × 225 with 40 between them. The row reaches the screen's edge, so four and a
    sliver of the fifth fit across, as on Android. Before, three fitted.
  - Every card shows its number, its name, three lines of its description, and its running time
    (or what's left of it), as Android's cards. Before, only the focused card had its
    description, and the running time sat on the picture.
  - The watched tick is the same small one as on cards.
- **A film's rows:** Down to the cast brings up the cast and the row under it (More Like This, or
  extras) both in full. Before, the second row was cut off.
- **An episode's card** on Home, in search and elsewhere opens its show's page on that episode.
  The page shows its season and focuses it, as Plex does and as Android's linked episodes do.
  Before, it opened a page of the episode on its own.
- **An actor's circle** grows as a whole when focused. Before, the photo zoomed inside a circle
  that stayed still.

## Decisions

- **Down from Play on a show** goes to the season tabs, as Android's, at the owner's request
  (27 November). Plex goes straight to the episodes. Opening an episode from Home still lands on
  that episode.
- **The page margins:** tvOS's own 80 pt margin and nothing more. That is as far left as Apple
  recommends, because some TVs cut off the edges of the picture.

## Checks

- `swift test --package-path ArcKit`: all pass (1 skipped), including the new test for an episode
  opening its show.
- `swiftc -parse` on every changed file; every `L()` key exists (`extra.` is the known prefix
  match); `git diff --check` is clean.
- The owner tried these screens in a tvOS simulator (VibeView) over several builds on
  `claude/apple-tv-polish` and asked for the follow-ups above.
- Nothing was tried on a real Apple TV.

## Logging

None new: layout and focus only.
