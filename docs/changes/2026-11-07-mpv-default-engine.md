# mpv is the default engine, Apple's player the fallback (7 November)

## What changed

- **The player uses mpv by default** (`EngineChoice.make()`). It tells Arc it plays almost
  everything as it is (`DeviceCaps.mpv()`):
  - containers: MKV, MP4, WebM, MPEG-TS, AVI and others;
  - video: H.264 (10-bit too), HEVC, AV1, VP9, VC-1 and MPEG-2;
  - audio: AAC, Dolby Digital (Plus), TrueHD, DTS, FLAC and others;
  - HDR: Dolby Vision 5, 7 and 8, HDR10, HDR10+ and HLG.

  So Arc sends files untouched, and converts only for bandwidth (away from home) or the truly
  exotic.
- **Apple's player as the fallback:** if mpv reports it can't play a file, the player stops it,
  switches to Apple's player with Apple's own capabilities, and asks Arc again from the same
  position, once. The screen swaps to the new picture surface.
- **Choosing Apple's player:** the `player.engine` default set to `apple` makes this Apple TV use
  Apple's player throughout, for comparing the two or diagnosing a file. There's no menu for it
  yet.
- **Match Content with mpv:**
  - Before a stream starts, the player tells the engine what the picture is
    (`prepareDisplay(DisplayHint)`), taken from the file's video track as the server read it:
    dynamic range, frame rate and size. It's plain SDR when Arc converts the video.
  - mpv loads paused, asks the TV for that mode (an `AVDisplayCriteria` from a format description
    with the range's colour tags, Dolby Vision as `dvh1`, and the frame rate), waits while the TV
    switches (up to 6 s), then plays.
  - Stopping returns the TV to its usual mode. Apple's player still reads the criteria from the
    stream itself.
- **ArcKit additions** (all from existing v1 fields): a stream's `frame_rate` and
  `dolby_vision_profile`, and the caps' `max_bit_depth` (10 for mpv, so 10-bit H.264 isn't
  converted).

## Limits

- **Nothing here has been built or run yet.** The owner asked to save Actions minutes, so there
  was no macOS build. It needs one before a device test.
- **Converted streams:** with mpv, the stream clock of Arc's converted HLS streams (which start at
  an offset) is unchecked. If mpv reports the source's timestamps rather than zero-based ones,
  positions would be off for converted playback. Direct play (the usual case now) isn't affected.
- **Audio and subtitle tracks** still come through Arc's decisions (another audio track means a
  repackaged stream, and picture subtitles are burned in) rather than mpv's own track switching.
  That's the next step.
- **Real Apple TV checks** are owner checks: the mode switch, Dolby Vision, HDR10+, 7.1 PCM from
  TrueHD, Atmos via Dolby Digital Plus, and frame pacing.

## Logging

- **On the switch to Apple's player:** a warning ("mpv couldn't play this file; Apple's player
  instead") after the existing "the stream didn't play" line, with the method and mpv's error
  string. No URLs.
