# mpv engine, step 1: the package and the engine (7 November)

## What changed

- **The package.** `project.yml` adds edde746/mpv-build's `MPVKit` (mpv, FFmpeg and the
  libraries they use, as XCFrameworks), pinned by commit.
- **The engine.** `ArcTV/Player/MPVEngine.swift` implements `PlaybackEngine` over libmpv:
  - the patched `avfoundation` video output, drawing into an AVSampleBufferDisplayLayer;
  - VideoToolbox decoding;
  - Dolby Digital (Plus) handed to Apple's decoder, everything else decoded to PCM;
  - the sign-in header, a start position, and play, pause, seek and speed;
  - waiting, ended and failed events.
- **Not used yet.** Nothing chooses the engine for any file.
- **App size.** The macOS build now writes `app-size.txt`, the Debug app's size and its frameworks,
  next to the screenshots.

## Why

The owner chose mpv over AetherEngine because it is long established and cross-platform. The
reasons are in `docs/plans/arc-engine.md`.

## Limits

- No Match Content (the TV's mode switch), track lists or engine choice yet. Those are the next
  steps.
- Nothing has been played through it. Video and audio need a real Apple TV.

## Logging

The engine reports failures through the existing player log (`failed(reason:)`, mpv's error
string, no URLs). mpv's own log messages aren't requested yet.
