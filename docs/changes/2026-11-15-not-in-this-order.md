# Episodes outside the episode order: "Not in This Order" (15 November)

The owner's next feature for the Apple TV app (via the server chat). It follows arc-roku#12 and
the web's show page.

## What changed

A show's page used to show only the seasons of its episode order. Episodes the profile has that
the order doesn't include (Arc's `unplaced`, in `GET /api/v1/series/{id}/seasons`) appeared
nowhere, so they couldn't be played from the Apple TV. That broke Arc's rule that nothing
silently disappears.

- **The show's page:**
  - After the seasons there's a **Not in This Order** tab, the web's name for it.
  - Its episodes show their name with no "E4", because the order gives them no number.
  - Select plays one, as in any season.
- **Play, Resume and Up Next** still follow the order's seasons only, as on the web. The tab is
  numbered -1, which the page's Play already leaves out (it takes seasons from 1, then
  specials).
- **The player:** for an episode from that tab, the **Episodes** card lists the other episodes
  outside the order.
  - Its tiles have no "S1 · E8" code.
  - The title line and the Info card show the episode's name without one.
  - There's no Previous Episode button, since these have no order to step back through.
- **ArcKit:**
  - `SeasonsResponse.unplaced`, which treats missing or null as none (both are in the v1 contract);
  - `SeasonsResponse.tabs(unplacedName:)`, the seasons and then the extra tab;
  - `tab(containing:)`, the episode's tab with only its playable episodes, for the player;
  - `Season.isUnplaced`;
  - two tests.

## Decisions

- **No explanation line.** The web has a sentence under its tab ("You have these episodes, but
  … doesn't include them"). On the TV, as on Roku, the tab's name stands alone. The episode row
  has no room for a paragraph.
- **A tab, not a row:** the Apple TV page shows one season at a time under tabs, so "Not in This
  Order" is the last tab, where the web puts it. Roku uses a row because its seasons are rows.

## Checks

- `swift test --package-path ArcKit` on Linux (Swift 6.2.1): 55 tests, 1 skipped (the live
  server test), 0 failures. Before this change: 53 tests, 1 skipped, 0 failures.
- The edited tvOS files parse (`swiftc -parse`), and `Localizable.strings` passes `plutil -lint`.
- **Not compiled for tvOS:** the macOS build hasn't been run, and the tab hasn't been seen in the
  simulator. The stand-in Arc sends no `unplaced`, so the walk-through wouldn't show it.
- Not checked on a real Apple TV.

## Also to know

- **With arc-apple#19:** that PR adds a season tab menu (Mark Season as Watched). Whichever of the
  two merges second should leave that menu off this tab, because it has no season number to send.

## Logging

- **Debug:** the player logs `the episode is outside the show's order` when it plays one.
- **Warning:** a failed seasons load logs as before (the title page's warning; debug in the player).
- Nothing names titles, ids or addresses.
