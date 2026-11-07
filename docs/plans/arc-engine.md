# Arc's own playback engine (plan, 7 November)

Apple's player can't open MKV, can't decode TrueHD or DTS, and is fussy with Dolby Vision
profiles 5 and 8. So the server repackages almost every file before the Apple TV can play it.
The aim is to play files untouched wherever the Apple TV's hardware can, with our own engine
built around FFmpeg. It sits behind the existing `PlaybackEngine` protocol; Apple's player stays
for streams the server converts (remote, lower quality, old formats).

## How it works

| Stage | Done by |
|---|---|
| Reading the file over the network (MKV, MP4, TS…), with the sign-in header | FFmpeg libavformat (custom AVIO over URLSession) |
| Video: HEVC, H.264, AV1 | packets wrapped as CMSampleBuffers → `AVSampleBufferDisplayLayer` (VideoToolbox, hardware) |
| Dolby Vision 5 / 8.1 / 8.4 | format description built ourselves: `dvh1`/`dvhe` with the `dvcC`/`dvvC` record from the container, so the TV switches mode and P5 isn't shown as plain HEVC (the green/purple picture) |
| HDR mode and frame rate | `AVDisplayManager.preferredDisplayCriteria` from the stream, waiting for the TV's mode switch |
| Dolby Digital / Digital Plus (incl. Atmos) | compressed to `AVSampleBufferAudioRenderer` (Apple's Dolby decoder) |
| TrueHD, DTS, DTS-HD MA, FLAC, PCM… | FFmpeg libavcodec decode → multichannel LPCM (up to 7.1) to the same renderer |
| Sound and picture in step | `AVSampleBufferRenderSynchronizer` (Apple's own clock) |
| Subtitles | ASS/SSA: the app's libass renderer; PGS: FFmpeg's decoder, drawn as pictures; SRT/WebVTT as now |
| Picture-in-picture | `AVPictureInPictureController` with the sample-buffer layer |

## Licence

FFmpeg built LGPL only (no `--enable-gpl`), as dynamic frameworks, so the App Store exception on
arc-media-server#80 stays possible. Only libavformat, libavcodec (the decoders we need),
libavutil and libswresample. Other players' code (Plezy, Plozz, KSPlayer, mpv) is GPL: ideas
only, never copied.

## Steps

1. **FFmpeg for tvOS**: an LGPL xcframework build in the macOS workflow, cached so it builds once.
2. **The test**: an MKV with Dolby Vision 8.1 and TrueHD 7.1 plays on the device. Checked on the
   owner's Apple TV: the TV's Dolby Vision mode, the receiver showing 7.1 PCM, seeking, no stutter.
3. **The engine**: buffering and network hiccups, seeking (keyframe then accurate), track
   switching, subtitles, rate (Watch Together), stall and error reporting.
4. **Choosing**: the playback request tells the server the app takes these containers and codecs
   untouched; the server answers direct play, and the app picks Arc's engine for direct plays and
   Apple's player for HLS.
5. Later: Dolby Vision profile 7 (rewrite to 8.1), HDR10+.

## Not claimed until seen on a real Apple TV

Mode switching, Dolby Vision, HDR10, Atmos, 7.1 PCM, frame pacing.
