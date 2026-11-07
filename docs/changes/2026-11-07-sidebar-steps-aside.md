# The sidebar steps aside on opened pages, and no longer dims the page

## What changed

- **Opened pages fill the screen.** While a page is open on top of a place's first page (a
  title, a collection, a person, a folder), the sidebar's icons and the margin kept for them go
  away, so a title's artwork and words use the whole screen. Back returns to the first page, and
  the sidebar comes back with it. Each place's page stack reports how deep it is (`ReportDepth`);
  only the place showing counts.
- **No dimming when the sidebar opens.** The glass panel behind the names is enough to read them;
  the dark wash across the left of the page is gone.

## Why

The sidebar's reference design (a "pinned sidebar": icons always showing, a glass panel when
open) hides itself on title pages and doesn't dim the page. These two were where Arc differed.

## Decisions

- The sidebar is Arc's own, not tvOS's adaptable sidebar, which collapses to a small floating
  pill when shut (see 2026-11-01-icon-sidebar.md). This stays.
- The current place keeps its grey disc rather than a tint: the app has no UI colour.
- The list doesn't scroll yet; it fits about 14 places. Scrolling with faded edges can come when
  someone has more libraries than that.

## Logging

None: layout only.

## Limits

- Checked in the tvOS simulator's walk-through screenshots, not on an Apple TV.
