# The reference look: bigger cards, About, badges, posters and the episode browser

The first two steps of `docs/plans/reference-look.md`.

## What changed

- **Bigger cards everywhere.** Posters are 236x354 (were 200x300), wide cards 512x288 (were
  384x216): about four wide cards or six posters across the screen, as the reference design
  has them, so art and names read from a sofa. Card names and row titles are a size up. The
  library grid still fits six posters a row.
- **The title page's About section.** Under an "About" heading:
  - an About card across the top: the tagline (or an episode's name) in bold, then the overview;
  - Details, Crew and Playback side by side beneath it, each with more in it:
    - Details: Released, Runtime, Content Rating, Genres (and the original title when it
      differs);
    - Crew: Directed by, Written by, Studio;
    - Playback: Server, Profile, Video, Audio, Bitrate, Size, Edition and the file's name.
  - The cards no longer scroll sideways.
- ArcKit's `MediaFile` reads the file's `path` (already in /api/v1), for the file's name.
- **Quality badges are capsules**, as the reference design draws them: the resolution filled
  white ("4K", "1080p", "720p", "SD"), then outlined capsules split by a line ("DV | HDR10",
  "DD+ | 5.1", "Atmos"), and "SDR" for a picture without HDR (`Quality.capsules`, with tests).
- **Library posters:** a show's episodes still to watch in a dark tab at the top right (the tick
  once all are watched), and the year and length under the name ("2011 · 25m"). Filter's button
  names what's shown: All, Unwatched, a genre, or Filtered for several.
- **Continue Watching and Up Next show the show's own picture** with its logo on it, rather than
  the episode's still, so a row of shows is easy to tell apart (`MediaCard.withShowArt`).

## Decisions

- No Ratings card: Arc's ratings are paused.
- The Playback card says which profile is watching ("Profile"), and leaves out the connection
  (home network or remote), which the app doesn't know for certain yet.

- **A show's seasons and episodes, as the reference moves to them.** Down from a show's buttons,
  the page scrolls so the season tabs sit under the show's logo (small, centred at the top) and
  the artwork darkens a little. Moving along the tabs shows that season straight away; coming
  back to them lands on the season showing. Episodes are large cards (512x288) with their
  length on the picture (or the resume strip), "E1 · Name" under them, and the overview under
  the focused one only. An episode not out yet is dimmed with "Releases 8 Nov"
  (`Item.upcomingRelease`, with a test); it takes the focus but doesn't play. Up from the tabs
  returns to the hero.

## Walk-through

Steps 13a–13c show the episode browser: coming down to it, an episode focused, and the next
season chosen from the tabs.


Home keeps a title opened earlier, and the sidebar now steps aside on opened pages, so the
walk-through presses Back until Home's first page before choosing Home again.

## Logging

None: layout only.

## Checks

`swift test --package-path ArcKit` passes. The walk-through screenshots (04-06 Home, 07-08b the
title page, 17-18 a library) show the new sizes and the About section. Not yet seen on an
Apple TV.

## The episode row peeks under a show's hero (7 November, later)

From the owner's photos of the reference app on their TV. On a show's hero, the season tabs are
folded away and the top of the episode thumbnails peeks in at the bottom of the screen. Down brings
the tabs back with the episodes, under the logo. Arc showed the tabs there and no episodes. The
tabs now fold to no height and are masked while the hero has the focus, with the same 0.9 s curve
as the rest of the move.

A film's hero has nothing peeking under it, as in the owner's photo of the reference. A spacer below
the hero starts the next row (Trailers & Extras, Related…) just under the screen, and Down scrolls
to it as before.

The cast row now comes first under the hero, above Trailers & Extras, Related and the rest. For a
show it comes straight after the episodes.

## The walk-through uses the owner's titles

So screenshots compare directly with the owner's photos of the reference, the stand-in's recorded
Interstellar is now **Spider-Man: Brand New Day** (TMDB 969681) and Firefly is **Dexter:
Resurrection** (TMDB 259909). Their pictures come from TMDB as before.
- Dexter has Season 1 (ten episodes, watched, named "Episode n") and Season 2:
  - E1 Risky Business, ready to watch;
  - E2 Young Blood, releasing 8 November;
  - E3 Fallen, releasing 15 November.
- The walk-through picks Dexter on Home. On the season tabs it moves Left, from Season 2 (where
  the show opens, on its next episode) to Season 1.
- Re-recording the fixtures with `record.py` would bring the scratch library's titles back.

On a film, Down from the hero now brings the first row (the cast) up under the hero's buttons,
which stay in view at the top, as in the owner's photo. Up goes back to the whole hero. tvOS's own
scroll had moved the hero off the screen. To tell the hero from the rows, the cast and the
trailers carry focus keys (`cast|…`, `extra|…`).

A title's page opens with Play focused, as the reference does. tvOS had been picking the nearest
button, and on a show that was the watched tick. Play carries the focus key `hero|play`. The
page's logic treats that key, or no key, as "on the hero". The walk-through's 08 is now taken after
one Down, the view in the owner's photo.

The hero's mask now reaches 80 points past the hero. It used to sit right at the buttons, and it
cut off the bottom of a focused button's lift and shadow. The artwork's fade is gentler, as in the
owner's photos of the reference:
- top to bottom, full until 60% of the way down, then to 45% (it was 15% at 60% and gone at the
  bottom);
- left to right, from 50% on the left to full past the middle (it was 12%).

Before, the page read as a dark panel over the overview and the peeking episodes.
