# Apple TV: the owner's 27 November list

The owner's list after trying the Apple TV app, with arc-android as the reference.

## What changed

- **Home and Recommended:** the row the focus moves into lands at the foot of the screen, going
  down or back up, with the rows above it in view. The first row brings the hero back. This
  matches Android's `FootScroll`, Kodi's rows and Plex. Before, going up left the row at the top.
- **Card names** sit under the art lined up on the left, as in the other Arc apps. This applies
  on Home, Recommended, Library, Collections and everywhere else cards appear.
- **The corner badge** is white with black text, as Arc's other controls and Android's
  `WatchBadge`. It shows a show's unwatched count or a new season's count; otherwise, a watched
  title gets a white tick, 36 px across, inside the top-right corner. Before, the count was
  black, and the tick was 48 pt and sat on the corner.
- **Recently Added** follows the server's grouping (arc-media-server, 12 and 13 November):
  - A season's card says "Season 2" or "Specials", with its count of new episodes as the badge.
  - A whole show's card says "3 new episodes".
  - Before, a season's card said "Season 2 · 3 new", and a whole show's card said nothing.
- **Films on Home and Recommended** show the year and edition ("2008 · IMAX") with no running
  time. Codex's commit from `codex/movie-edition-labels` is included, so this PR replaces that
  branch. The Library grid and the title page keep the running time.
- **The title page** sits lower and further left, as Android's:
  - The words start about 96 px from the left.
  - A film's buttons sit about 80 px above the bottom.
  - A show's buttons sit just above its season tabs, which now peek in at the bottom. Before,
    the tops of the episodes peeked in. Down still goes straight to the episode to watch next.
- **Episodes:** each card is 400 × 225 with 40 between them, so four and part of a fifth fit
  across, as on Android. Before, three fitted. The watched tick is the same small one as on cards.
- **An episode's card** on Home, in search and elsewhere now opens its show's page on that
  episode. The page shows its season and focuses it, as Plex does and as Android's linked
  episodes do. Before, it opened a page of the episode on its own.
- **Server screen** matches Android's:
  - one left-aligned column over Arc's soft glow;
  - the address with Connect beside it;
  - one line under them, which says it's connecting, what went wrong, or the port note;
  - then the servers found on the network.
- **Sign-in screen** matches Android's: the numbered steps and buttons on the left, the code in
  large boxes on the right.
- **PIN:** Arc's own PIN step replaces the system dialog. It matches the web's and Android's:
  - the profile's picture and name, "Enter your PIN" and four boxes, with the next box ringed in
    white;
  - a number pad beside them (focus starts on 5), because the Siri Remote has no number keys;
  - the fourth digit checks the PIN, as Plex does;
  - a wrong PIN shakes the boxes, empties them and says "Try again";
  - Back or Profiles returns to the profiles.

## Decisions

- **Down from Play on a show** still goes to the episode to watch next, not to the season tabs as
  on Android. Only what peeks in has changed. Plex also goes to the episodes. The alternative is
  to go to the tabs first, as Android does.
- **The running time** is dropped only from Home and Recommended, which is what the list asked
  for. The Library grid keeps it as a way to tell films apart. A show's poster keeps its
  episodes' length.
- **The page margins** were matched to Android's by measuring the last simulator screenshots.
  The page uses a 40 pt inset inside tvOS's own margin.

## Checks

- `swift test --package-path ArcKit`: 95 tests passed, 1 skipped, 0 failures. They include new
  tests for Recently Added counts, for an episode opening its show, and Codex's edition test.
- `swiftc -parse` passed on every changed screen. Every `L()` key exists; `extra.` is the known
  prefix match. `git diff --check` is clean.
- The macOS build and simulator walk-through are on this PR's `[build]` run, with screenshots on
  the `ci-screenshots` branch.
- The first walk-through caught a bug in the new Home scrolling. With the Watch Together row on
  top, entering the first row of titles sent the page back to the top, which left the focused card
  below the screen. It's fixed: only the topmost row brings the hero back.
- The stand-in server has no profile with a PIN, so the walk-through doesn't reach the new PIN
  screen. It was checked by reading the code only.
- Nothing was tried on a real Apple TV.

## Logging

A refused PIN logs at debug ("profile PIN refused"), with no PIN or profile in it. There are no
other new logs: the rest is layout and focus.
