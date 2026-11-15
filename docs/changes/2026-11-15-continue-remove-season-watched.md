# Remove from Continue Watching, and marking a whole season watched (15 November)

The first item from the feature-parity review: two everyday actions that the web and the
Android TV app have and the Apple TV app lacked.

## What changed

**Remove from Continue Watching:**
- Holding Select on a card in **Continue Watching** or **Up Next** on Home, or in a library's
  Recommended **Continue Watching** row, now offers **Remove from Continue Watching**. These are
  the same rows the web offers it on.
- It calls `DELETE /api/v1/home/continue/{id}` (already in the v1 contract). Arc takes the title
  out of Continue Watching and Up Next without marking it watched and keeps its resume point.
  For an episode, the whole show goes until something of it plays again.
- Home and the library page then read their rows again, so the card goes.
- Cards in other rows, and the title page's own buttons, don't offer it.

**Mark a season watched or unwatched:**
- On a show's page, holding Select on a season tab offers **Mark Season as Watched**, or **Mark
  Season as Unwatched** once every episode that's out is watched.
- It calls `PUT /api/v1/items/{series}/played` with `{"played": …, "season_number": n}`
  (already in v1). The number is the season as the profile's episode order numbers it, which is
  how `series/{id}/seasons` lists the tabs.
- Episodes not out yet don't count towards a season being watched. A season with nothing out
  shows no menu.
- The page reads again afterwards and stays on that season. Otherwise it would move to the
  season of the next episode to watch.

**ArcKit:**
- `ArcAPI.removeFromContinue(_:)` and `ArcAPI.setPlayed(seriesId:seasonNumber:_:)`.
- `Season.watched` and `Season.markable`.
- Four tests: the requests and bodies, a refused removal, and when a season counts as watched.

## Decisions

- Follows the web's choice of rows (Continue Watching, Up Next and Recommended's Continue
  Watching). Android offers it only in Home's Continue Watching row.
- The menu item is called "Remove from Continue Watching", as on the web, also in Up Next,
  because Arc removes the title from both.
- The season menu is on the season tabs, as Plex for Apple TV has it. The Android app doesn't
  have one yet.

## Checks

- `swift test --package-path ArcKit` on Linux (Swift 6.2.1): 57 tests, 1 skipped (the live
  server test), 0 failures. Before this change: 53 tests, 1 skipped, 0 failures.
- The edited tvOS files parse (`swiftc -parse`), and `Localizable.strings` passes `plutil -lint`.
- **The macOS build hasn't been run,** so the tvOS app hasn't been compiled with these changes and
  the menus haven't been seen in the simulator. The walk-through doesn't cover them yet.
- Not checked on a real Apple TV.

## Limits

- The card goes once the rows have been read again, not instantly as on Android. After that the
  focus may move to a neighbouring card.
- If Arc refuses, nothing changes on screen. The failure is only logged, as for the other card
  actions.

## Logging

Through the card menu's existing paths, with no ids, names or addresses:
- debug `title action done: remove from continue` / `title action done: season watched|unwatched`;
- warning `title action remove from continue failed: <error type>` /
  `title action season watched failed: <error type>`;
- `ArcAPI` logs the routes `home/continue/{id}` and `items/{id}/played` as it does for every request.
