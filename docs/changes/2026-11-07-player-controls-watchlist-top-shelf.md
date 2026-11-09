# Player controls from the reference video, Watchlist filters, Top Shelf

## What changed

**Player controls** (`ArcTV/Player/PlayerOSD.swift`), matched to the owner's video of the
reference player:

- The title is the show's name, large, with "S2, E4 • the episode's name" above it (a film:
  its title).
- **Buttons:** three small round buttons sit right of the title, in the order Playback, Audio, Subtitles. They're always there; Up from the picture lands on Subtitles.
- **Timeline:**
  - thin, and split at the chapters;
  - a small upright marker;
  - the time played under the marker, with the play/pause sign;
  - the time left at the right end.
- **Tabs:** Info, Chapters, Cast, Episodes (and Watch Together in a room).
  - **Info:** the episode's picture, its name and overview, then a line such as "S2 · E4 · 24m · 24 Oct 2026" with the quality capsules. Small round Restart and Previous Episode buttons sit at the top right. How the stream reaches the Apple TV (direct, repackaged or converting, and the engine) is in small text at the end of the bottom line.
  - **Chapters:** glass tiles with the chapter's name and time; the current one has a play sign.
  - **Cast:** a glass tile per person, with a round photo, name and role. The cast is the episode's own, or else the show's.
  - **Episodes:** the season's episodes as pictures, with "S2 · E1" on each and the name below. Select plays one.
- **Menus:** each opens above its button, with its name at the top. Choices are ticked at the right.
  - **Playback:**
    - Zoom Mode (Normal or Zoom, which fills the screen);
    - Playback Speed (0.5× to 2×; Select moves to the next speed; not shown in a Watch Together room, where the room sets the pace);
    - then Quality and Version as before.
  - **Audio:** the tracks.
  - **Subtitles:** Off and the tracks.
- Zoom is the display layer's gravity for both engines. mpv's avfoundation output hands frames on whole, so mpv's own pan-and-scan isn't used. Speed and zoom are kept when Apple's player takes over from mpv.

**Watchlist:**
- Pills at the right of the title:
  - All, Movies or TV Shows;
  - Date Added (Arc's order, newest first), Title, or Release Date.
- `PageScaffold` gains an optional accessory beside the title for this.

**Top Shelf:** a new extension (`ArcTopShelf`, TVServices) shows the profile's most recent Continue Watching titles (up to 10, with up-next episodes, as Home's row lists them).
- It uses the picture Home's card uses, and shows a progress bar.
- Select opens the title's page on Home; Play plays it. This works through `arcmediaserver://open/<id>` and `arcmediaserver://play/<id>`. On a cold start the link waits until the profile is chosen.
- tvOS fetches Top Shelf pictures itself and can't send Arc's sign-in header. So the extension downloads them with the header into the app group's container and hands over the files. Pictures of titles no longer shown are removed.
- **Sharing with the app:**
  - The app and the extension share the server's address through the app group `group.org.arcmediaserver.apple`.
  - They share the token through the keychain access group `org.arcmediaserver.apple.shared`, which both list first, so new items land there. `Keychain.swift` moved to `ArcTV/Shared/`.
  - Installs from before this re-save their token once at launch so it moves into the shared group.

## Decisions

- **Not built:** Enhance Dialogue and Reduce Loud Sounds (in the reference's Audio menu) and the subtitle Style button.
  - The first two are Apple's own audio processing for its player. With mpv, Dolby Digital (Plus) goes to Apple's decoder untouched, so there's nothing to apply them to.
  - Subtitle style lives in the profile's preferences on the server (Settings), as the web's.
  - Logged on arc-media-server#80.
- **Top Shelf profile:** the Top Shelf follows the profile last chosen on this Apple TV (the device's session on the server), as other apps' Top Shelves follow the current user.

## Limits

- **Not built yet:** nothing here has been built or run yet; it waits for the next macOS build, which isn't run on every change to save Actions minutes.
- **Signing:**
  - The app group and the shared keychain need a signing team on a real Apple TV.
  - Unsigned builds (CI's device build) carry no entitlements. There the Top Shelf finds no server and tvOS shows the app's own picture.
  - Simulator builds are signed to run locally with the entitlements.
- **Device checks:** the Top Shelf's file pictures and the links need checking on a real Apple TV.

## Logging

- **Top Shelf:**
  - each load logs how many titles and pictures it showed, and how long it took;
  - a failed Continue Watching load is a warning, naming the error type only;
  - a failed picture is a debug line.
- **App:** following a Top Shelf link logs at info; a failed lookup is a warning.
- **Player:** missing cast or episodes are debug lines.
- Nothing logs URLs, ids or the token.
