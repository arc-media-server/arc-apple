# Backdrops cards: four across, logo centred

## What changed
Home's **Backdrops** card style (Continue Watching in the shared screenshot library) was 512×384,
so only three fitted across the screen, and the title's logo sat at the bottom left where it
crowded the resume strip (Breaking Bad's broke over two lines next to the bar).

- The card is now 360×270, still the web's 4:3, so four and a bit fit across, as on the web and
  Android (owner, 22 November).
- The art darkens towards the bottom and the logo is centred low on it, at most 72% of the
  card's width and 26% of its height, with a soft shadow: the web's `ArcArtwork` and Android's
  `BackdropArt`. On a part-watched title it sits above the resume strip instead of beside it.

## Checks
- The macOS build and simulator walk-through (run 45085650734) pass; Home's screenshot looked at
  (`2026-11-22-backdrop-cards/home.jpg`): four cards and part of a fifth, logos centred.
- Not checked on a real Apple TV.

## Logging
None (layout only).
