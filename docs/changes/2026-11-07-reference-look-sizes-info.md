# Bigger cards, and the title page's About section

The first two steps of `docs/plans/reference-look.md`.

## What changed

- **Bigger cards everywhere.** Posters are 250x375 (were 200x300), wide cards 512x288 (were
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

## Decisions

- No Ratings card: Arc's ratings are paused.
- The Playback card says which profile is watching ("Profile"), and leaves out the connection
  (home network or remote), which the app doesn't know for certain yet.

## Logging

None: layout only.

## Checks

`swift test --package-path ArcKit` passes. The walk-through screenshots (04-06 Home, 07-08b the
title page, 17-18 a library) show the new sizes and the About section. Not yet seen on an
Apple TV.
