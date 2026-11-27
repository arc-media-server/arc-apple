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
- **The title page** sits lower and further left:
  - The words start at tvOS's own margin, 80 px from the left. Before, they started at 160 px.
  - A film's buttons sit about 80 px above the bottom.
  - A show's buttons sit just above its season tabs, which now peek in at the bottom. Before,
    the tops of the episodes peeked in.
- **A show's page flows as Android's:**
  - Down from Play goes to the season tabs, on the season showing.
  - The tabs and episodes land at the foot of the screen, with the page above them, and the
    artwork dims behind them.
  - Up from the tabs brings the whole page back.
  - Before, the artwork and words slid away and the show's logo appeared in the middle at the
    top, as Apple's TV app does.
- **Episodes:**
  - Each card is 400 × 225 with 40 between them.
  - The row reaches the screen's edge, so four and a sliver of the fifth fit across, as on
    Android. Before, three fitted.
  - Every card shows its number, its name, three lines of its description, and its running time
    (or what's left of it), as Android's cards. Before, only the focused card had its description,
    and the running time sat on the picture.
  - The watched tick is the same small one as on cards.
- **Library header:** Recommended, Browse and Collections are each their own glass pill, as Sort
  and Filter are, with the one showing in white. Before, they shared one big pill. The bar sits
  closer to the top, and the rows of posters are closer together, so two whole rows show with
  their names and years.
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

- **Third round, after build 143:**
  - Down to the episodes now lands the tabs and episodes at the foot every time, with the
    descriptions in full. tvOS's own scroll for the focus used to win over Arc's and cut them off.
  - Home's first row lands at the foot as the others do, from the moment Home opens, so its names
    show in full under the hero. Before, they were cut off until the focus moved.
  - An actor's whole circle grows when focused. Before, the photo zoomed inside a circle that
    stayed still.
  - On a film's page the cast comes up closer under the buttons.
  - Library: the pill bar sits at the top of the safe area and the gaps are smaller, so the
    second row's names and years show in full.

- **Fourth round, after build 144:**
  - The profile picker matches Android's:
    - round avatars with no card behind them;
    - a white ring and a slight grow on focus;
    - a lock badge on the rim for a profile with a PIN;
    - the name underneath, grey until focused.
    Before, each profile sat on a grey card with a "Locked" line under its name.
  - The library's pill bar sits in the same place on Recommended as on Browse and Collections.
    Over Recommended's hero it sat 15 points higher.
  - On a film, Down to the cast brings up the cast and the row under it (More Like This, or
    extras) both in full, where Down to that row leaves them. Before, the second row was cut off.

- **Fifth round, after build 145:**
  - Library: more room under the pill bar, so a focused poster in the first row no longer
    touches it. The rows are a little closer together, so the second row still fits.
  - PIN screen: the number keys and the PIN boxes are Liquid Glass, as the Profiles and Sign Out
    buttons already were. The focused key stays white with black text.

## Decisions

- **Down from Play on a show** goes to the season tabs, as Android's, at the owner's request
  (27 November). Plex goes straight to the episodes. Opening an episode from Home still lands on
  that episode.
- **The running time** is dropped only from Home and Recommended, which is what the list asked
  for. The Library grid keeps it as a way to tell films apart. A show's poster keeps its
  episodes' length.
- **The page margins:** the title page uses tvOS's own 80 pt margin and nothing more. That is
  as far left as Apple recommends, because some TVs cut off the edges of the picture.

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
- The owner tried build 142 in a simulator and asked for the second round: the title page's
  margin, the show page's flow, the episode cards, the fifth episode's sliver and the library
  header.
- The stand-in server has no profile with a PIN, so the walk-through doesn't reach the new PIN
  screen. It was checked by reading the code only.
- Nothing was tried on a real Apple TV.

## Logging

A refused PIN logs at debug ("profile PIN refused"), with no PIN or profile in it. There are no
other new logs: the rest is layout and focus.
