# The Apple TV app's first version

The start of Arc for Apple TV, following the Android TV app's screens and rules.

## What changed

- **ArcKit**, a Swift package with no UI:
  - the `/api/v1` client: sign-in with a TV code, profiles, prefs, Home's rows, browsing,
    seasons, playback, progress, keeping a conversion alive, cast links;
  - the models, which tolerate missing and new fields;
  - Home's rows arranged as on the web, following the profile's library order, with the
    Watchlist at its place, seasonal rows, and collections and playlists last;
  - the playback clock for converted streams.
- **The tvOS app** (SwiftUI):
  - connect to a server by address;
  - sign in with a code entered in Arc (Link a Device);
  - "Who's watching?" with PINs, under the server's name;
  - Home, whose backdrop follows the focused card;
  - title pages, with a show's seasons and episodes;
  - the player.
- **The player** uses Apple's own player behind a small `PlaybackEngine` interface, with Arc's
  own controls: the title, the timeline and times, Play/Pause, and left/right to skip 10 s. Back
  hides the controls, then closes the player.
  - Arc decides how each title plays from what Apple's player takes: MP4; H.264 and HEVC; AAC,
    MP3, Dolby Digital and Dolby Digital Plus; HDR10, HLG, and Dolby Vision profile 8 when the TV
    is in HDR.
  - Everything else is repackaged or converted by Arc, as for the Chromecast. TrueHD and DTS
    become Dolby Digital Plus 5.1.
  - Streams are opened through cast links (`POST /cast`), which carry their own token, because
    Apple's player fetches a converted stream's pieces without the app's header.
  - Match Content is asked for, so the TV switches to the title's dynamic range and frame rate.
  - A stream that won't play is asked for again once, repackaged or converted, as the web player
    does.

## Decisions (on arc-media-server#80)

- **Apple's player first, behind the engine interface.** AetherEngine is deferred because of the
  patent uncertainty around its optional Dolby/DTS parts (FEL composing especially).
- **Dolby Vision is reported as profile 8 only.** Arc tags copied HEVC as `hvc1`, which suits
  profile 8's HDR10 base but would show profile 5 in the wrong colours. Profile 5 is converted.
- **Unknown HDR rather than "SDR only"** when the TV isn't in HDR at the moment, as on Android.

## Checks

- `swift test --package-path ArcKit`: 14 tests (addresses, models, Home rows, the client against a
  stand-in server), all passing on Linux with Swift 6.2.
- The tvOS app is built by the macOS workflow (results in the PR).
- **Not yet run on an Apple TV or in the simulator.** That needs a Mac, or TestFlight with an
  Apple Developer account.

## Logging

- Sign-in outcomes, connecting, the playback method with Arc's reasons, and stream failures (the
  error domain and code). Progress and keepalive failures, and Home rows that failed (as a count).
- Routes only: no ids, URLs or tokens. The token is kept in the Keychain.

## Limits (next)

- No sidebar or library pages yet. There's no search, no audio or subtitle choice in the player
  (Arc's default audio track plays, and subtitles are off), no Up Next, and no Skip Intro.
- No app icon or Top Shelf image yet.
- No accessibility pass yet.
