# A second playback engine: mpv (plan, 7 November)

Apple's player can't open MKV, can't decode TrueHD or DTS, and is fussy with Dolby Vision
profiles 5 and 8. So the server repackages almost every file before the Apple TV can play it.
The aim is to play files untouched wherever the Apple TV's hardware can.

## Decision

Use the patched mpv/FFmpeg build at github.com/edde746/mpv-build (SwiftPM product `MPVKit`,
pinned by commit), behind the existing `PlaybackEngine` protocol. Apple's player stays for streams
the server converts (remote, lower quality, old formats).

Why not our own engine around FFmpeg: the hard Apple TV parts are already done and tested in that
build. Building them again would take months. Those parts are:
- the AVSampleBufferDisplayLayer output, so the TV switches into Dolby Vision and HDR modes;
- Dolby Vision profile 7 to 8.1 conversion and HDR10+;
- frame-pacing fixes;
- TrueHD/DTS decoding to 7.1 LPCM (and tvOS 26's spatial path).

Why not AetherEngine, which the reference app uses: it is younger and depends on one
developer. mpv has years of use behind it, and the same core runs on Android if Arc's Android app
ever needs it.

The player screen is Arc's own SwiftUI screen in Apple's style, over both engines. AVKit's
ready-made screen needs AVPlayer, so mpv can't use it.

## Licence

The build is GPL-3.0, with FFmpeg's GPL parts enabled. Arc is AGPL-3.0-only, which may be
combined with GPL-3.0 (section 13), and Arc's source is public, so using it is allowed.

The App Store is the same grey area every GPL app there is in. The App Store exception
(`LICENSE-EXCEPTION.md`, decided in arc-media-server#477) covers Arc's own code only, not mpv's or FFmpeg's. If a contributor ever
objected and the app were removed, Arc falls back to Apple's player.

The build's Apple-specific patches are mainly by edde746, with Alex Kim (vo_avfoundation) and
kristofferR (tvOS 26 spatial audio). They could be asked to release them as LGPL to remove the
grey area, but nothing depends on that.

We use the binaries as published and write our own Swift wrapper. We never copy Plezy's app code;
it is GPL too, and could be combined, but our wrapper is built for Arc's `PlaybackEngine`.

## Steps

1. **Add the package.** Pin a commit of mpv-build. Check the app size and that the tvOS build links
   in the macOS workflow. Done on `claude/apple-engine`: `ArcTV/Player/MPVEngine.swift`
   implements `PlaybackEngine`, not yet chosen for any file. The build writes `app-size.txt`
   beside the screenshots.
2. **`MPVEngine: PlaybackEngine`**, using libmpv's C API:
   - set the options (`vo=avfoundation`, `hwdec=videotoolbox`, the audio outputs);
   - observe properties (time-pos, pause, demuxer cache, track-list) on a serial queue;
   - pass the sign-in header with `http-header-fields`;
   - report stalls and errors.
3. **TV mode:** set `AVDisplayManager.preferredDisplayCriteria` from the stream's frame rate and
   dynamic range, waiting for the mode switch before playing.
4. **Tracks and subtitles:** use mpv's own track list and libass, with the player's existing menus.
5. **Choosing the engine:** the playback request tells the server which containers and codecs the
   app takes untouched. The server answers direct play, and the app uses mpv for direct plays and
   Apple's player for HLS.
6. **The test on the owner's Apple TV:** an MKV with Dolby Vision 8.1 and TrueHD 7.1. Check the
   TV's Dolby Vision mode, the receiver showing 7.1 PCM, seeking, no stutter. Then Dolby Vision 5,
   HDR10, and Dolby Digital Plus Atmos.

## Not claimed until seen on a real Apple TV

Mode switching, Dolby Vision, HDR10, HDR10+, Atmos, 7.1 PCM, frame pacing.
