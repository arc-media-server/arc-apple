# The player's controls, in the reference design's arrangement (7 November)

From the reference player's code (the owner's player photos haven't come yet; once they do, the
details follow them).

## What changed

`ArcTV/Player/PlayerOSD.swift` draws the controls. The player screen keeps the state.
- **Bottom left:** the title (with "S1 · E7 · Show" above an episode's).
- **To its right, round glass buttons:** **Subtitles**, **Audio** (only with more than one track)
  and **Playback**. Each opens its menu **above the button**, as a glass list with a tick by the
  current choice:
  - Subtitles: Off and the tracks;
  - Audio: the tracks;
  - Playback: Quality, then Version when there's more than one.

  Back closes a menu, back to its button.
- **The timeline:** a thicker bar with a knob and chapter marks. The time played is on the left and
  the time left on the right, with the timeline thumbnail as before.
- **The tab row under it:** **Info**, **Chapters** (when the file has some) and **Watch Together**
  (in a room).
  - Focusing a tab slides its card up from the bottom, and the title, buttons and timeline step
    aside.
  - **Info:** the picture, title, overview and a line saying what's playing, e.g.
    "4K · Dolby Vision · Dolby Atmos · Direct play · mpv".
  - **Chapters:** a row to jump to.
  - **Watch Together:** who's in the room, Invite, Leave and End for Everyone.
- **The remote on the picture:**
  - Left and Right skip 10 s.
  - **Up** goes to the buttons.
  - **Down** opens the Info card with its tab focused.
  - Back leaves the controls, then hides them, then closes the player, as before.
- **Hiding:** the controls hide after **4 s** of no input, or **9 s** with a card up. They stay
  while a menu is open or the video is paused. If the buttons had the focus, it goes back to the
  picture first.
- **What it replaced:** the old side panel (Subtitles, Audio, Quality, Version, Chapters and Watch
  Together in one list down the right) is gone. Its contents moved into the menus and cards above.
- The walk-through's player shots follow the new controls: 10b is the Info card, 10c the
  Subtitles menu, 10d the Playback menu.

## Limits

- **Not built or run yet,** to save Actions minutes, so the look and the focus moves are unchecked.
- **Not done:** playback speed, audio and subtitle delay, subtitle style, and the Episodes and Cast
  tabs the reference also has.
- **The menus still go through Arc** (another audio track repackages; picture subtitles are burned
  in) rather than mpv's own track switching.

## Logging

Nothing new. Choosing a track, quality or version goes through the existing player model, which
logs as before.
