# Seeing the Apple TV app run: a simulator walk-through

## What changed

- **A walk-through in the tvOS simulator.** `UITests/ArcTVUITests/WalkThrough.swift` is a UI test that
  presses the Siri Remote's buttons through the app and keeps a screenshot of each screen. It covers
  the server address, the sign-in code, "Who's watching?", Home, a title page, the player playing and
  paused, and Home again.
- **A stand-in Arc for it.** `UITests/StandIn/serve.py` is a small Python server that answers
  `/api/v1` from `fixtures/answers.json`:
  - The answers were recorded from a scratch Arc with tools/testmedia's library, by `record.py`.
  - Every picture is a coloured placeholder, so no artwork is kept.
  - Every title plays `fixtures/sample.mp4`, a 12-second test pattern, through a cast link.
  - A sign-in code is approved on its third check.
- **The macOS workflow** now runs the walk-through after the build:
  - It uploads the screenshots as an artifact.
  - It also adds small JPEG copies to `runs/<run id>/` on the `ci-screenshots` branch, which is
    only ever appended to, together with the stand-in's log and any crash report. Agents whose
    network can't reach artifact storage can read them with git.
  - It still runs only when asked, skips pushes that only change Markdown, and a newer run on the
    same branch cancels an older one.

## Bugs it found, fixed here

- **"Who's watching?" focused Sign Out.** While the profiles load, Sign Out is the only thing on
  screen and takes the focus, so the first press of Select signed the Apple TV out. Focus now
  moves to the first profile when they appear, as Plex's picker does.
- **Home focused the profile button.** Focus now starts on the first title, as Plex's Home does.
- **Pressing Play crashed the app.** The player asked the window for its display manager (Match
  Content) without checking that it has one. The simulator's windows don't, and the crash report
  showed "unrecognized selector" in `applyDisplayCriteria`. The player now checks first. The
  player's AVFoundation callbacks are also `@Sendable`, so they no longer inherit the main actor
  and trap when called on another queue.
- **A title page showed an empty grey bar when the logo couldn't be loaded.** `TitleLogo` shows
  the title's name instead.

## Checks

- The macOS workflow (Xcode 16.4, tvOS simulator):
  - The ArcKit tests pass and the app builds.
  - The walk-through passes, and its screenshots were checked. In run 41320219585, the sample clip
    played in the simulator, pause showed Arc's controls (title, timeline, times), and Back returned
    to Home.
- **Not checked on an Apple TV.** Not checked: Match Content, HDR, Dolby Vision, audio formats, or
  playback of real files and conversions. The simulator only shows that the app's flow and
  AVPlayer work with a plain H.264/AAC MP4.

## Logging

- The app logs nothing new.
- The workflow keeps the stand-in's request log and the app's crash reports with the screenshots.
- The stand-in records no tokens: it accepts any token.
