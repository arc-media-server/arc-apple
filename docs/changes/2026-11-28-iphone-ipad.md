# iPhone and iPad app (first version)

## What changed

A second app target, **ArcMobile**, for iPhone and iPad (iOS 18+), in this repository beside the
Apple TV app. It shares ArcKit, the player (`PlaybackEngine` with mpv and Apple's player), the
app's state (`AppModel`, sign-in, Keychain, the app group), the data behind screens and the string
catalogue with the Apple TV app; only the screens are its own.

- **Sign-in:** the server screen (address field and the servers found on the network), the link
  code (with **Open Link a Device**, which opens the server's `/link` page on the device itself),
  Who's Watching and the PIN sheet (number pad, four boxes, a shake on a wrong PIN).
- **Tabs:** Home, Libraries and Search in a tab bar that becomes a sidebar on iPad
  (`.sidebarAdaptable`). The profile picture in each page's bar opens Settings.
- **Home:** the profile's rows as arranged on the web (the same `HomeModel` as the Apple TV's),
  each scrolling sideways and snapping to cards, then the play queue's row. Pull to refresh.
- **Cards:** artwork with progress, the white count badge or watched tick, the name and its line
  under it (the TV's words, `S1 · E4`). A tap opens the title (or plays an episode part-way
  through); touching and holding gives the title's actions (the TV's `TitleActions`).
- **Title page:** the backdrop fading into the title's colours, the logo, the details line, Play
  (Resume / Play S1 · E4), Play from Beginning and Shuffle, the actions under ⋯, the overview
  (tap for all of it), a show's season menu and episodes (still, progress, `S1 · E4 · Title`,
  length, overview; dimmed with the release day when not out), the season's ⋯ (mark watched,
  shuffle), Starring and More Like This.
- **Libraries:** the libraries in the profile's order, the Watchlist and Playlists; a library's
  grid with Titles/Collections, a Sort menu (the TV's sorts, Reverse Order, Unwatched Only, Clear
  Filters) and paging; collections, playlists, people, genres and Videos folders.
- **Search:** iOS's search field, following the typing, with films, shows, episodes,
  collections, people and genres.
- **Settings:** a sheet with the profile, Switch Profile, the playback preferences (from the
  server, as the web's and the TV's), the player choice, automatic sign-in, Use Another Server,
  Sign Out (confirmed) and About (versions, server, licences, attribution).
- **Player:** full screen, turning an iPhone to landscape. Tap to show or hide the controls (they
  hide after four seconds of playing); double tap a side to skip 10 seconds; drag the timeline;
  pinch to fill. The controls are close, the title, subtitles and audio, ⋯ (speed, zoom, from the
  beginning), back 10, play/pause, forward 10 and the timeline. Skip Intro / Recap / Credits and
  Up Next (with Auto-Play's countdown) in the corner; the play queue follows as on the TV. Control
  Center and the lock screen's Now Playing work through the shared `NowPlaying`. Sound keeps
  playing with the screen locked (background audio).
- **Shared code moved** (no behaviour change on Apple TV): `Route`/`Browse`, `HomeModel`,
  `PlayRequest`, `loadPage`, the item and card text helpers, `TitleActions`, the brand views and the
  player's text helpers into `ArcTV/Models`, `ArcTV/Components` and `ArcTV/Player/PlayerText.swift`.
  Match Content (`AVDisplayCriteria`) stays tvOS-only behind `#if os(tvOS)`.
- **CI:** the Build workflow builds the iOS app and walks it in an iPhone simulator
  (`UITests/ArcMobileUITests`), with screenshots beside the Apple TV's on `ci-screenshots`.

## Decisions

- **iOS's conventions over the TV's layout:** a tab bar, not a sidebar or top menu; navigation
  pushes with swipe-back; menus on touch and hold; Settings as a sheet. Plex for iOS and Apple's TV
  app do the same. Arc stays Arc through its look: dark only, white controls with black text, no
  colour but the logo's, the same words and episode format as every Arc app.
- **Three tabs (Home, Libraries, Search):** Plex for iOS has Home, Library and Search too (with
  more for Live TV and downloads, which Arc's apps don't have yet). Watchlist and Playlists sit in
  Libraries rather than taking tabs. The alternative is a tab per library, as the TV's sidebar
  lists them; that crowds the bar on iPhone.
- **One player, same engines:** the mpv engine is the default, as on Apple TV; Apple's player is
  in Settings. Picture in Picture and AirPlay aren't in this version (they need Apple's player's
  layer or route picker and their own work).
- **Not yet on iOS:** Watch Together (the invite is hidden on iOS; joining needs its own screens),
  the library's Recommended tab (its helpers are private to the TV's LibraryView, which an open PR
  changes), pre-roll videos, theme music, trickplay thumbnails on the timeline, downloads and
  casting. Each can follow without changing what's here.
- **Settings code is a second copy** of the TV's preference saving, for now: SettingsView is
  changed by an open PR (#36), so sharing it waits until that's merged.

## Checks

- `swift test --package-path ArcKit`: 97 tests, 1 skipped (the live server test), 0 failures.
- The Build workflow (macOS): see the PR for the run and its results.
- Not checked: anything on a real iPhone or iPad (playback, audio, HDR, rotation, Control Center).
  No device was available.

## Logging

The iOS screens log as the TV's do, through `ArcLogApp` (`ArcLog`, subsystem
`org.arcmediaserver.apple`): load failures of a page, a title action's outcome, preference changes,
playlist adds and the player moving on. The player's own logging is the shared `PlayerModel`'s. No
tokens, addresses or URLs are logged.
