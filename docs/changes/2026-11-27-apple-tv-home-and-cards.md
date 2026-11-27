# Apple TV: Home, Library and cards (the owner's 27 November list)

Part of the owner's 27 November list for the Apple TV app, with arc-android as the reference. The
list is split over four PRs: this one (Home, Library and cards), the title page, sign-in and
profiles, and the player.

## What changed

- **Home and Recommended:** the row the focus moves into lands at the foot of the screen, going
  down or back up, with the rows above it in view. The first row lands there too, from the
  moment Home opens, so its names show in full under the hero. This matches Android's
  `FootScroll`, Kodi's rows and Plex. Before, going up left the row at the top, and the first
  row's names were cut off until the focus moved.
- **Card names** sit under the art lined up on the left, as in the other Arc apps, everywhere
  cards appear.
- **The corner badge** is white with black text, as Arc's other controls and Android's
  `WatchBadge`. It shows a show's unwatched count or a new season's count; otherwise a watched
  title gets a white tick, 36 px across, inside the top-right corner. Before, the count was black,
  and the tick was 48 pt and sat on the corner.
- **Recently Added** follows the server's grouping (arc-media-server, 12 and 13 November): a
  season's card says "Season 2" or "Specials" with its count of new episodes as the badge; a whole
  show's card says "3 new episodes". Before, a season's card said "Season 2 · 3 new", and a whole
  show's card said nothing.
- **Films on Home and Recommended** show the year and edition ("2008 · IMAX") with no running
  time. Codex's commit from `codex/movie-edition-labels` is included, so this PR replaces that
  branch. The Library grid and the title page keep the running time.
- **Library header:** Recommended, Browse and Collections are each their own Liquid Glass pill, as
  Sort and Filter are, with the one showing in white. Before, they shared one big pill. The bar
  sits at the top of the safe area, in the same place on Recommended as on Browse and
  Collections, with room under it so a focused poster in the first row doesn't touch it. The rows
  of posters are closer together, so two whole rows show with their names and years.
- **Sidebar:** Arc's white logo at the top, the mark while it's shut and the whole logo while it's
  open.

## Decisions

- **The running time** is dropped only from Home and Recommended, which is what the list asked
  for. The Library grid keeps it as a way to tell films apart. A show's poster keeps its
  episodes' length.
- **The sidebar logo** is new for Arc: Android's sidebar has none. Apple's own apps put theirs
  there.

## Checks

- `swift test --package-path ArcKit`: all pass (1 skipped), including the new Recently Added test
  and Codex's edition test.
- `swiftc -parse` on every changed file; every `L()` key exists; `git diff --check` is clean.
- The owner tried these screens in a tvOS simulator (VibeView) over several builds on
  `claude/apple-tv-polish` and asked for the follow-ups above.
- Nothing was tried on a real Apple TV.

## Logging

None new: layout and focus only.
