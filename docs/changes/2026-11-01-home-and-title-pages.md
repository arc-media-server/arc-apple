# Home and title pages follow Plozz

## What changed

**Cards.** Names sit centred under the art. A part-watched title on a wide card (Continue
Watching) carries a resume strip on the art: a play mark, how far through and the minutes left,
over a soft shade, with the show's logo on the picture when Arc has one. Its line under the name
is short ("S8 · E6"). Posters keep the thin bar and "12m left".

**Hero (Home and Recommended).** The content rating sits in an outlined box before the genres
(and a film's year); an episode's season, number and name get their own line.

**Title page.**
- The hero: logo, rating box and genres, the overview, then the year, length and the file's
  quality badges (4K, DV HDR10, DD+ 5.1, Atmos) and the buttons. "Starring …" and "Director …"
  sit bottom right.
- Below: seasons and episodes, Trailers & Extras, **Related** (was More Like This), **Cast** (the
  actors, as round photos; directors and writers move to the Crew card), Collections.
- At the foot, glass cards: **About** (tagline and overview), **Details** (released, studio,
  original title), **Crew** (directed by, written by) and **Playback** (video, audio, size,
  edition). They take the focus so the remote can reach them.

ArcKit reads each file's streams, size and container, and a title's studio, release date and
original title and language, from `GET /api/v1/items/{id}` (all already in the v1 contract).
`Quality.badges` turns a file into the badges; tests cover 4K Dolby Vision with Atmos, DTS-HD
MA with DTS:X, the default audio track, HLG, SD and files with no streams.

## Why

The owner's Plozz screenshots (1 November) of Home and Spider-Man: Brand New Day's page.

## Decisions

- No Ratings card and no critic or audience scores: Arc's ratings are paused, so the page shows
  only what Arc has. In white, not Plozz's blue tick.
- Badges describe the source file, not what this TV will output (as the web's labels).
- No "New season" pill on the hero yet: Arc's API doesn't say when a season starts.

## Limits

Checked in the tvOS 26 simulator against the stand-in, whose titles are given a made-up cast,
crew, studio and a 4K Dolby Vision file with Atmos. Not checked on a real Apple TV.

## Logging

No new requests or failure paths: the page uses the same `items/{id}` load, which already logs a
failure once. Nothing new to log.
