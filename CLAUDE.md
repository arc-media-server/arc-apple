# Arc for Apple: notes for AI agents

The Apple client for Arc Media Server, in Swift and SwiftUI: Apple TV (tvOS) first, then iPhone
and iPad (iOS/iPadOS) in this same repository, sharing ArcKit (the API client, models and
playback logic), as the Android app does with TV and phone. The server is
arc-media-server/arc-media-server (Go, with a web app); the Android TV app is
arc-media-server/arc-android and is the closest model for this one. The owner (GitHub: JonzaUK)
drives product vision; agents (Claude, Codex) do most implementation. Read `README.md` and
`docs/changes/` (what was built and why). The server repo's CLAUDE.md and docs/API.md are the
wider context; decisions waiting for the owner are on arc-media-server#80.

## Workflow (same as the other repos)

- Everything goes through pull requests: never push to main, never force push. Work on the branch
  the session assigns (Claude: `claude/...`; Codex: `codex/...`). The owner merges.
- Before a PR, run the checks and list the real results:
  - `swift test --package-path ArcKit` (it runs on Linux too, with the Swift toolchain);
  - the macOS build: `.github/workflows/build.yml`, run from the Actions tab or by a push to an
    agent's branch whose commit message contains `[build]`. macOS minutes count ten times, so
    batch fixes and run it before a PR, not on every push.
- Record each change in `docs/changes/YYYY-MM-DD-<slug>.md`; commit messages have a summary, a
  body and the Co-Authored-By trailer. Keep working without check-ins; log product decisions on
  arc-media-server#80; stop only for risky or irreversible things.
- Never mark device, playback, HDR, Dolby Vision or audio checks done without evidence from a
  real Apple TV (or iPhone/iPad, for the iOS app). Never point tests at the owner's server,
  data or keys.

## Rules

- **API:** only `/api/v1`, through ArcKit's `ArcAPI`. It's promised stable (the server's
  `docs/api-v1-contract.txt`); unknown fields are ignored (`@Default` for absent ones). If the app
  needs something v1 lacks, make an additive server PR and link the two PRs.
- **Playback engine:** the screens talk only to `PlaybackEngine` (ArcTV/Player). Apple's player
  (`AVPlayerEngine`) is behind it for now; another engine (e.g. AetherEngine) may replace it later
  without changing the screens. Don't use AVPlayerViewController or engine types in screens.
- **Feel:** native to each platform: on Apple TV the focus engine, `.card` buttons and Back
  always working; on iPhone/iPad, iOS conventions (touch, navigation stacks). Arc identity
  through the wordmark. No UI colour (owner, 1 November): chosen and main controls are white
  with black text, as the sidebar's; the teal is the logo's alone. Dark only; artwork-led Home
  (no banner). The player's controls follow the web and Android players' set and order. Brand
  colours live only in `ArcTV/App/Theme.swift`.
- **Plex first:** match how Plex for Apple TV (and Plex for iOS, for the iPhone/iPad app)
  behaves unless there's a clear reason not to; log differences on arc-media-server#80. Settings come from the server (the profile's prefs) rather
  than app-only options where Arc already has them.
- **Text:** every user-facing string in `ArcTV/Resources/en.lproj/Localizable.strings`, used via `L()`.
- **Logging:** `ArcLog` (os.Logger, subsystem org.arcmediaserver.apple, category Arc): outcomes and
  failures, detail only at debug; never tokens, passwords or full URLs. Each PR says what it logs.
- **Licence:** AGPL-3.0-only until the App Store exception on arc-media-server#80 is decided.

## Layout

```
ArcKit/          Swift package, Foundation only: ArcAPI, models, Home rows, playback clock (+ tests)
ArcTV/App/       app entry, AppModel (server, sign-in, profile), Keychain, Theme, L()
ArcTV/Screens/   server, sign-in code, profile picker, Home, title page
ArcTV/Player/    PlaybackEngine, AVPlayerEngine, DeviceCaps, PlayerModel, PlayerScreen
ArcTV/Components/ artwork loading (with the sign-in header), cards
(iOS)           the iPhone/iPad app will be a target beside ArcTV/, sharing ArcKit (not started)
project.yml      XcodeGen project (Arc.xcodeproj is generated, not kept)
```
