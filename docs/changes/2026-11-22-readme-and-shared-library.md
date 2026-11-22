# README in the other public apps' style, and the shared screenshot library in the walk-through

## What changed
- **README:** rewritten in the same layout as arc-android's, arc-tv's and arc-kodi's: the
  logo, badges, a large Home picture, what the app is, a picture grid, what it does, installing
  (building onto an Apple TV with Xcode, as there's no TestFlight yet), developers' notes, the
  layout and the licence with the App Store exception and TMDB's credit. The logos are copied
  into `docs/brand/`; the pictures are in `docs/screenshots/`.
- **Stand-in answers** (`UITests/StandIn/fixtures/answers.json`) re-recorded from arc-media-server's
  shared screenshot library (`node tools/screenshots.mjs --serve`), so the simulator screenshots
  show the same titles as every other Arc app (Dune: Part Two, Breaking Bad, Severance…) instead of
  the owner's reference titles.
- **`record.py`:** chooses the first profile before recording, so Home's answers are that
  profile's (it used to record them before any profile was chosen); tolerates rows that come as
  an object with `items`; records searches for "arrival" and "dune".
- **Walk-through:** opens Breaking Bad for the show steps and types "dune" in Search. Its last step
  asks the stand-in to drop its Watch Together rooms (`POST standin/no-rooms`), restarts the app
  and photographs Home on Continue Watching, as most people see it: the README's main picture.
- **Workflow:** the copies on the `ci-screenshots` branch are 1280 wide (they were 960), the size
  the READMEs use, because the full-size artifact is out of reach from some agent sessions.

## Decisions
- Installing says to build with Xcode onto the Apple TV, with a free Apple Account (7 days) or a
  paid membership (a year), until the app is on TestFlight. Plex's app is on the App Store, so it
  has no equivalent.

## Checks
- `swift test --package-path ArcKit`: in the macOS build (Swift isn't installed in this session's container).
- The macOS build and simulator walk-through, with the README pictures taken from its screenshots.
- Not checked on a real Apple TV.

## Limits
The README pictures are simulator captures against the stand-in, not a real Apple TV.

## Logging
None (docs, test fixtures and the UI test).
