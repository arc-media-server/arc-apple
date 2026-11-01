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
confusing: two ways to play the same thing.

## Limits

Checked in the tvOS 26 simulator against the stand-in only.

## Logging

Removes code paths only; nothing new to log. (The hero's Watchlist failure warning goes with
its button; the card menu's actions keep theirs.)

## Also: real pictures in the screenshots

The owner asked for screenshots that give more of a feel for the app. The stand-in Arc's titles,
cast and descriptions were already real (recorded from a scratch Arc with TMDB); now its pictures
can be too. When the build has a `TMDB_API_KEY` Actions secret, the stand-in fetches each title's
poster, background and logo from TMDB by the recorded TMDB id, and cast photos by name, and
caches them for the run. Episodes show their show's background. Without the secret, or when TMDB
has nothing, it draws the placeholders as before. The key goes only to TMDB and is never logged;
a picture TMDB can't give is logged by its Arc path and the error's type.

## Also: a narrower sidebar

The owner found the open sidebar wide. It is Arc's own (not tvOS's), and now opens to 360 points
(was 440) with slightly smaller icons and names.
