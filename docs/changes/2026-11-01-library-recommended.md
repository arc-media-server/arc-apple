# Library pages open on Recommended, with Plozz's pill bar

## What changed

A film or TV library now opens on **Recommended**: the library's rows from Arc (Continue Watching,
Recently Released, Recently Added, Because you watched…, Top Rated and the rest, in the shared
layout's order and looks) under the same full-screen hero as Home. The pill bar across the top
reads Recommended, Browse, Collections (and Folders for Other videos libraries, which have no
Recommended and still open on Browse). On Recommended the bar floats over the top of the hero,
so it shows as the page opens with the focus on the first title, and fades while the focus is
further down than the first row, so it never covers a row. Sort and Filter show beside the bar on Browse.

Home and Recommended share one view (`HeroRows`): the focused title's background, logo or name,
details, Play, Watchlist and Info, with the rows beneath. Focus starts on the first title.

ArcKit reads `GET /libraries/{id}/recommended` and titles each row from its type in the viewer's
language, as the web does (`recommendedTitle`), using Arc's English title for a type it doesn't
know. The stand-in Arc makes Recommended rows from each library's titles.

## Why

The owner's screenshots of Plozz (1 November): a library opens on its recommendations with a pill
bar of Recommended, Browse, Collections and Playlists. Plex also opens a library on Recommended.

## Decisions

- Playlists aren't in the library's bar: Arc's playlists aren't per library, and they're in the
  sidebar.
- The library's name isn't shown above the bar, as in Plozz; the sidebar shows which library it is.
- "Browse" names the grid of all titles (the web says Movies or Shows), following the owner's
  screenshots.
- Row "see all" isn't offered yet; Browse has the whole library.

## Limits

Checked in the tvOS 26 simulator against the stand-in only. The stand-in's rows are made up from
the recorded titles, not Arc's real recommendations.

## Logging

Loading Recommended goes through the same `loadPage` as the other library views: a failure is
logged once with the view's name, and the load time and row count at debug.
