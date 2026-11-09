# Swipe to scrub on the Siri Remote

## What changed

**Swiping:**
- A sideways swipe across the Siri Remote's touch surface scrubs, as in tvOS's own players.
- The video pauses and the marker follows the finger, with the timeline picture and its chapter name above it.
- Further swipes carry on from where the last one left the marker.
- Left and Right clicks while scrubbing move the marker 10 seconds.

**Ending a scrub:**
- A click or Play plays from the marker.
- Back puts the marker back where it was.
- Up or Down leaves scrubbing for the buttons or the cards.
- Either way the video plays on if it was playing before the swipe.

**Scale:** a swipe across the whole surface moves about a quarter of the title, and at least 2.5 minutes, so short episodes stay fine-grained.

**How it works:**
- `SwipeCatcher` puts a pan recognizer for the remote's (indirect) touches on the window while the player is showing. It only counts mostly-sideways movement.
- The swipe also sends move commands. Those are ignored for half a second after the finger last moved, so a swipe never also skips 10 seconds.

Scrubbing is off while the buttons, cards, a menu, the lobby or a problem are showing. In a Watch Together room, the pause and the jump go to the room as other seeks do.

## Limits

- The feel (the quarter-title scale, the 1920-point surface width the maths assumes, the half-second guard) needs tuning on a real Siri Remote.
- Nothing here has been built yet; it waits for the next macOS build.
- Picture-in-picture is not planned for Apple TV.

## Logging

None added: scrubbing is ordinary input. Seeks that need a new stream already log at debug in `PlayerModel`.
