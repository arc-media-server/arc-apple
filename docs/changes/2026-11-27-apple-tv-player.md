# Apple TV: player fixes and Playback Info

Found by the owner while trying playback in a tvOS simulator (VibeView), 27 November, plus
Playback Info ("stats for nerds") at their request.

## What changed

- **Episodes card:** only as tall as its row (the picture, the name and the focus lift), and its
  episodes scroll under the panel's rounded edge rather than past it. Before, the glass panel
  stretched almost to the bottom of the screen and the episodes ran out past its sides.
- **Down from the round buttons** (Playback, Audio, Subtitles) goes back to the timeline, where
  Down again opens Info. Before, nothing below them could take the focus (the tabs sit far to the
  left), so the controls had to be closed and opened again.
- **Up from a card** (Episodes, Chapters, Cast, Info) goes back to its tab. Before, tvOS often
  found nothing above a card and the focus stuck in it.
- **An open Playback, Audio or Subtitles menu** no longer flashes its focused choice. The player
  redrew the menu with every tick of the clock; the round buttons are now a view of their own.
- **Playback Info** ("stats for nerds"), as Android's. A tick in the Playback menu shows a glass
  panel at the top right over the picture, read again every second, until it's turned off there:
  - how it's playing (direct, repackaged or converted; mpv or Apple's player) and Arc's reasons;
  - the video as played (codec, size, frame rate), its dynamic range and whether it decodes in
    hardware;
  - the audio track (and what the engine is fed, if Arc converted it) and where the sound goes
    (Apple's Dolby decoder with Atmos kept, or PCM);
  - a picture subtitle Arc burns in;
  - the file's bitrate, the download speed, how much is buffered, waits and dropped frames;
  - this Apple TV's picture and sound output.

  Both engines report through `PlaybackEngine.stats`: mpv everything; Apple's player its size,
  frame rate and access log, with the codec and range then taken from the file. ArcKit's
  `StatsFormat` writes the values, with tests.

## Decisions

- **Playback Info stays up while watching** and takes no focus. Android's is a panel that takes
  the focus and closes with Back; on Apple TV it's more use watching the numbers change while the
  film plays. A tick in the Playback menu turns it on and off. Plex shows its own from its
  settings while playing.

## Checks

- `swift test --package-path ArcKit`: all pass (1 skipped), including Playback Info's values.
- `swiftc -parse` on every changed file; every `L()` key exists; `git diff --check` is clean.
- The owner tried the Episodes card and the buttons' Down in a tvOS simulator, with playback.
- Simulator playback is no evidence for HDR, Dolby Vision, Atmos or passthrough. Nothing was
  tried on a real Apple TV, so Playback Info's readings there are unchecked.

## Logging

None new: Playback Info only reads the engines' state for the screen.
