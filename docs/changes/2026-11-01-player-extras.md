# Player extras: quality, versions, chapters, timeline thumbnails, trailers

## What changed

- **Quality:** the player's glass panel (swipe down) has a Quality section: Original, then the
  web's limits (20 Mbps 1080p down to 720 kbps 360p), only those below the file's own bitrate
  and, away from home, within the server's limit. Choosing one asks Arc for a converted stream
  from the same place (`max_kbps`).
- **Version:** when a title has more than one file (editions, copies), a Version section lists
  them as the web does ("Director's Cut · 1080p · H.264 · 14 GB"); choosing one plays it from the
  same place.
- **Chapters:** the file's chapters, with their start times; choosing one jumps there and closes
  the panel. The chapter playing is ticked.
- **Timeline thumbnails:** moving left or right shows the picture at that point above the
  timeline for a few seconds, with the chapter's name, from Arc's trickplay sheets (when the
  library makes them; none is fine).
- **Trailers & Extras:** a row on the title page, as Plex's. Each plays in a simple player
  (Play/Pause, left/right 10 seconds, Back to close) through a cast link, because Apple's player
  can't send the sign-in header.
- The stand-in answers with two versions, three chapters, a high bitrate, a thumbnail sheet and
  two extras on films; the walk-through shows the thumbnail and the Quality section.

## Decisions

- The options panel now always opens on Down (Quality is always there), matching the web
  player's settings menu.

## Logging

Info on a version or quality change and on playing an extra (its kind); warnings when an extra
fails; debug for thumbnails found or missing. No URLs or tokens.

## Limits

Simulator only; not checked on a real Apple TV.

## Also: white instead of teal

The owner dropped a UI colour (1 November): the Play buttons, chosen options, season and
library pills and the watched ticks are white with black, as the sidebar's chosen place. The
teal stays only in Arc's wordmark. `arcGlassButton(prominent:)` tints glass white with black text.
