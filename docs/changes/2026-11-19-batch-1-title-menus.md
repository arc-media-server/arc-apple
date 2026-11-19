# Batch 1: star rating, Show Missing Episodes, Add to Playlist, max audio channels (19 November)

The first batch of Apple TV parity items from arc-media-server#476, in one PR so one macOS build
covers them. Each follows the Android app's version (arc-android `docs/changes/2026-11-16-*` and
`2026-11-18-max-audio-channels.md`). Shuffle Season was planned for this batch but moves to the next,
with Play queues: it plays through a server play queue, which the Apple TV app doesn't have yet.

## Your own star rating

- **Where:** a title's page (films, shows and episodes) gains a round star button, after the
  others. Its menu, **Your Rating**, lists ★★★★★ (5 of 5) down to ½ (0.5 of 5), with the current
  rating ticked and **Clear Rating** when there's one. The star is filled once rated.
- **Saving:** `PUT /api/v1/items/{id}/rating` (1–10, 0 clears; in the v1 contract), then the page
  reads the title again, as Watched and Watchlist do. `UserData.rating` reads it back.
- **ArcKit:** `ArcAPI.setRating`, `StarRating` (the choices, "★★★½", "3.5").

## Show Missing Episodes

- **Where:** in a season tab's menu (hold Select), after Mark Season as Watched: **Show Missing
  Episodes**, or **Hide Missing Episodes** while they're shown. Not on the Not in This Order tab.
- **What it does:** the page asks for `GET /api/v1/series/{id}/seasons?missing=1` and keeps it for
  as long as the page is open, as the web's switch. The season the menu was opened on stays chosen.
- **Missing episodes:** dimmed, with **Not on Disk** on the picture; they take the focus (to read
  the overview) but don't play. Play, Resume and Mark Season as Watched use episodes on disk only.
- **ArcKit:** `ArcAPI.seasons(seriesId:missing:)`.

## Add to Playlist

- **Where:** every card's menu (hold Select) and the title's page, for films, episodes and shows.
- **The list:** a glass panel at the right, like Watch Together's invite panel: "Add “Heat” to:"
  (or "Add every episode of “Firefly” to:"), then the profile's playlists with their counts. Smart
  playlists aren't listed. Choosing one adds it with `POST /api/v1/playlists/{id}/items`, closes the
  panel and says "Added “Heat” to Movie Night" at the top of the screen (or that it couldn't).
- **No playlists:** the panel says to make one on the web first. If they don't load: Try Again.
- **Code:** `PlaylistPanel` (ArcTV/Components); `Browse.addingToPlaylist` and `Browse.note`, hosted
  in `MainView`. **ArcKit:** `ArcAPI.addToPlaylist`, `PlaylistSummary.editable`.

## Maximum audio channels

- The player now sends `caps.max_audio_channels` (in the v1 contract): the most channels tvOS says
  the current sound output takes (`AVAudioSession.maximumOutputNumberOfChannels`: 2 for stereo,
  6 or 8 for a 5.1/7.1 receiver). Arc then mixes down only what the output can't play. Both engines
  send it; it's read for each new player. Anything outside 1–32 is left out (unknown). Retries keep it.

## Decisions

- **Rating as its own button, not a ⋯ menu:** the Apple TV page has no ⋯ menu yet; its actions are
  round icons, so the star is one more. Plex for Apple TV has Rate in its title's menu.
- **Ratings on title pages only,** not card menus, as on Android.
- **No new playlists from the TV,** as on Android: typing a name with the remote is slow.
- **One change note for the batch** rather than one per feature, to save effort (owner, 19 November).

## Checks

- `swift test --package-path ArcKit` (Linux, Swift 6.2.1): 69 tests, 1 skipped (the live-server
  test), 0 failures. Before: 64. New: rating saved and read, stars, playlists (smart ones not
  editable, the POST and its answer), `missing=1` only when asked, max channels sent only when known.
- The edited and new tvOS files parse (`swiftc -parse`); the strings file's lines are well formed.
- **Not compiled for tvOS:** the macOS build hasn't been run. Not tried in the simulator or on a real
  Apple TV; whether a real receiver reports 6 or 8 channels is unchecked.

## Logging

- Warnings, with the error type only: "playlists failed to load for Add to Playlist", "adding to
  a playlist failed", "title action rating failed".
- Debug: "missing episodes shown/hidden", "title action done: rating / added to a playlist", and
  "sound output channels: N" (or unknown) for each new player. No ids, names or addresses.
