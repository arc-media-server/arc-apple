# Title page: Play button, About and Playback cards (7 November)

Matches the owner's own screenshots of the reference design, checked against its code.

## What changed

- **Play is a glass button like the others.** It turns white only when it has focus. It's no longer
  white all the time.
- **Play labels say what will play** (`PlayLabel` in Cards.swift):
  - not started: "Play" for a film;
  - "Start watching · S2, E1" for a season's first episode;
  - "Play S21 E8" for any other episode;
  - part watched: a bar of how far through, then what's left, as "S5 E12 · 43m" for an episode
    or "1h 2m" for a film.

  The bar takes the label's colour, so it still shows on the white of focus.
- **About card** is headed by the title in bold, then the overview. It used to show the tagline.
- **Playback card**, in order:
  - Server;
  - Connection (Local network or Remote), from `/api/v1/auth/status`'s existing `local` field;
  - Profile;
  - Quality in words (`Quality.summary`: "4K · Dolby Vision · Dolby Atmos");
  - Bitrate, Size, Edition and the file's name.

  The separate Video and Audio lines are folded into Quality.
- **Crew card** says "Studios".
- **Watched**: the page's round watched button shows a filled tick once a title is watched.
- **Library**: the "N titles" count beside Sort and Filter is gone, as in the reference.

## Limits

- Connection is learnt once, when a profile is chosen. If the device moves network while the app
  is open, the line can be out of date until the next profile choice.
- Not checked on a real Apple TV yet.

## Logging

Nothing new. The status call is the existing sign-in status, and a failure there just leaves the
line out.
