# Arc for Apple: notes for AI agents

The Apple client for Arc Media Server, in Swift and SwiftUI: Apple TV (tvOS) first, then iPhone and
iPad in this same repository, sharing ArcKit (API client, models, playback logic). arc-android is
the closest model for it. Read `README.md` and `docs/changes/`.

**Shared rules:** arc-media-server's `docs/AGENT-RULES.md` applies here (workflow, decisions, Arc's
design, API, logging). Read it at the start of a session: `../arc-media-server/docs/AGENT-RULES.md`
when the server is checked out beside this one, otherwise from GitHub. The essentials:

- Pull requests only: never push to main, never force push. Commits end with the Co-Authored-By
  trailer only, no session links. A change note per change in `docs/changes/`.
- Never point tests at the owner's server, data or keys. Never mark device, playback, HDR, Dolby
  Vision or audio checks done without evidence from a real Apple TV (or iPhone/iPad).
- Only `/api/v1`, through ArcKit's `ArcAPI` (`@Default` for absent fields); if it lacks something,
  an additive server PR, linked.

## This app

- **Checks before a PR:** `swift test --package-path ArcKit` (runs on Linux too). For changes to
  screens, also run the macOS build (`.github/workflows/build.yml`, a push whose commit message
  contains `[build]`): it builds the app, walks it in the tvOS simulator and puts the screenshots on
  the `ci-screenshots` branch. The repository is public, so its runs cost nothing; still push
  `[build]` only once a change is ready to look at, not on every commit.
- **Playback engine:** screens talk only to `PlaybackEngine` (`ArcTV/Player`); Apple's player
  (`AVPlayerEngine`) is behind it for now. Never use AVPlayerViewController or engine types in
  screens.
- **Feel:** on Apple TV the focus engine, `.card` buttons and Back always working; on iPhone/iPad,
  iOS conventions. Plex for Apple TV (and for iOS) first. Arc identity through the white logo
  (arc-media-server `docs/brand`, in `Assets.xcassets`); colours only in `ArcTV/App/Theme.swift`. Settings come from the server (the profile's prefs)
  where Arc has them.
- **Text:** every user-facing string in `ArcTV/Resources/en.lproj/Localizable.strings`, via `L()`.
- **Logging:** `ArcLog` (os.Logger, subsystem org.arcmediaserver.apple, category Arc).
- **Licence:** AGPL-3.0-only with an App Store exception for Arc's own code (`LICENSE-EXCEPTION.md`,
  decided in arc-media-server#477); third-party code keeps its own licence.
- **Layout:** `ArcKit/` (Swift package, Foundation only, with tests), `ArcTV/App/` (entry,
  AppModel, Keychain, Theme, `L()`), `ArcTV/Screens/`, `ArcTV/Player/`, `ArcTV/Components/`;
  `project.yml` is the XcodeGen project (`Arc.xcodeproj` is generated, not kept).
