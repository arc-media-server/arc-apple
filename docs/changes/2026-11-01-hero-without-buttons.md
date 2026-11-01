# Home's hero has no buttons

## What changed

The hero on Home and on a library's Recommended no longer has Play, Watchlist and Info buttons.
It describes the focused title (background, logo or name, rating and genres, the episode line and
the overview) and the rows beneath are where you act: Select on a card plays a part-watched
episode or opens the title's page, and holding Select gives its actions (Play, Play from
Beginning, watched, Watchlist, Go to Show). On a library page, Up from the first row now goes
straight to the pill bar.

## Why

The owner (1 November) found a Play button on the hero above the Continue Watching row
confusing: two ways to play the same thing. Plozz's hero has no buttons.

## Limits

Checked in the tvOS 26 simulator against the stand-in only.

## Logging

Removes code paths only; nothing new to log. (The hero's Watchlist failure warning goes with
its button; the card menu's actions keep theirs.)
