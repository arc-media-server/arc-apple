# The reference look (plan)

The owner's reference screenshots (7 November) show the look this app is heading for: the same
direction as now (artwork-led, glass, white focus, icon sidebar), but bigger, with richer title
pages and a few touches the app lacks. Not every option the reference app has is wanted, only its
look and direction. Each step below is its own change with walk-through screenshots; the other
TV apps copy the result once it's settled.

## What already matches

- The icon sidebar: icons always showing, profile on top, a glass panel when open, no dimming,
  gone on opened pages.
- Home's hero: logo, rating box and genres over the focused title's artwork.
- The resume strip on wide cards (play mark, bar, minutes left), names centred under cards.
- Library pills (Recommended, Browse, Collections) with Sort and Filter at the right.
- The title page's hero: logo, rating box, genres, overview, year and length with quality
  badges, Starring and Director at the right, Play then round buttons, Related, round cast.

## The gaps, in order

1. **Bigger everything.** The reference fits about four wide cards or six posters across the
   screen; Arc fits about five and nine, so its art and words read small from a sofa.
   - Wide cards 384 to about 500 pt wide; posters 200x300 to about 260x390.
   - The library grid fills the width with six posters a row.
   - Row titles and card names a size up.
2. **Title page: the cards at the foot.** Section headings ("About"), cards in a grid that wraps
   rather than a sideways row, and more in each:
   - About: the title in bold, then the overview.
   - Details: Released, Runtime, Content Rating, Genres.
   - Crew: Directed by, Written by, Studios.
   - Playback: Server, Connection (home network or remote), Profile, Quality (4K · Dolby
     Vision · Dolby Atmos), Bitrate, Size, File.
   - Ratings stay out while Arc's ratings are paused.
3. **Badges** as small rounded capsules, with two-part ones for the format and its detail:
   `DV | HDR10`, `DD+ | 5.1`; the resolution (4K, 1080p) filled.
4. **Library grid cards:**
   - a show's unwatched episode count in a tab at the top right of its poster (a tick once all
     are watched);
   - a progress bar across a part-watched poster;
   - "2011 · 25m" under the name (year and length);
   - Filter's button names what it shows ("All", "Unwatched"), Sort's names the sort.
5. **Continue Watching art:** a show's own picture with its logo on it, rather than the
   episode's still, so a row of shows is easy to tell apart. The episode is named under it.

## Not taken from the reference

- The choice of navigation styles, themes and card styles (Arc keeps one good default).
- Colour in the interface (a blue tick for watched): Arc's controls stay white.
- Ratings (paused in Arc).
- Season pills with large episode cards, the "New season" capsule, and the episode line in
  Home's hero instead of the overview (not wanted, 7 November).
- A Trailer button: the Trailers & Extras row already plays a title's trailers. Arc only plays
  trailers that are the owner's own files (a Trailers folder or "-trailer" files beside the
  film), never ones fetched from video sites.

## Checks

Each step runs the walk-through (`[build]` on the branch) and its screenshots go in the PR. The
look on a real Apple TV is the owner's to confirm.
