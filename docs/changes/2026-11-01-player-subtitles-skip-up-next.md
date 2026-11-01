# Player: subtitles, audio tracks, Skip Intro and Up Next

## What changed

- **Subtitles**: swipe down in the player for Subtitles and Audio. Text tracks (in the file or
  beside it) are read as lines from Arc and drawn by the app in the profile's subtitle style
  (size, white or yellow, box/solid/none, bottom or top), lifted above the controls while they
  show. Picture tracks (PGS, VobSub) are drawn in by Arc, which converts the video to do it
  (`burn_subtitle`). Subtitles turn on by themselves following the profile's subtitle mode and
  language, as the web player chooses (`chooseSubtitle`, now in ArcKit with tests), and a choice
  in the player is remembered in the profile the same way.
- **Audio**: choosing another track asks Arc again from the same point (it may repackage or
  convert for it) and remembers the language.
- **Skip Intro / Skip Recap / Skip Credits** from Arc's markers. The button takes the focus when
  it appears, so Select skips, as on Plex. With Skip Intros Automatically on, intros and recaps
  are skipped once each by themselves.
- **Up Next**: for episodes, the next one in the profile's order (`/items/{id}/next`) shows at
  the credits (or in the last 30 seconds) with its picture, Play Now and Cancel. With Auto-Play
  on it counts down from 10 and plays it; it also plays when the episode ends.
- The card menu gains Play from Beginning for part-watched titles.
- The stand-in gives every title an intro marker, a subtitle track and lines, and answers
  `/next`; the walk-through screenshots the options and subtitles.

## Limits

- Quality choice, chapters, versions, timeline thumbnails and extras are still to come.
- Subtitle timing adjustment and size changes from the player aren't there yet (the web's
  Settings change the style).
- Checked in the simulator against the stand-in only; not on a real Apple TV.

## Logging

The player logs at info when the audio track changes and when the next episode plays, a warning
when subtitle lines or a preference fail to load or save, and at debug the automatic subtitle
choice, how many lines loaded and automatic skips. No addresses or tokens.
