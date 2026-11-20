# Episode numbers written one way

The owner's rule for every Arc app (arc-media-server `docs/AGENT-RULES.md`, "Episode numbers",
arc-media-server#493): "S1 · E4" everywhere, a special is "Special 3", and "·" is the only
separator.

## What changed

- **One place builds the number.** ArcKit's `Item.episodeCode` says whether an episode is
  numbered (season and number), a special (season 0) or unplaced (outside the show's order). The
  app's `episodeCodeText` turns it into "S1 · E4" or "Special 3", and `episodeLine` adds the name
  where the episode is the subject ("S1 · E4 · Pilot"). The strings are `episode.code`,
  `episode.special` and `episode.with_title`; `card.episode`, `card.episode_short`,
  `card.episode_code` and `player.episode_line` are gone.
- **Cards:** the line under the show's name is now just "S1 · E4". Before, a wide card that wasn't
  started also had the episode's name on it.
- **Title page:** the Play button reads "Play S21 · E8", "Start watching · S1 · E1", or
  "S5 · E12 · 43m" beside the progress bar (was "S21 E8", "S1, E1" and "S5 E12"). The episode
  list under the season tabs reads "S1 · E4 · Pilot" (was "E4 · Pilot").
- **Player:** the title line reads "S2 · E4 · Pilot" (was "S2, E4 • Pilot"). Up Next, the Info
  card, the Episodes card and Now Playing use the same code.
- **Home hero:** unchanged in form ("S1 · E7 · Safe"), and specials now read "Special 3".
- **Top Shelf:** "Show · S1 · E4" as before, and a special is now "Show · Special 3". It used to
  be "Show · S0 · E3".

## Checks

- `swift test --package-path ArcKit`: 89 tests, 1 skipped, 0 failures. The new
  `EpisodeCodeTests` covers numbered, special, unplaced and film.
- `swiftc -parse` on every changed Swift file.
- Every `L()` key exists in the catalogue.
- No macOS build, at the owner's request. Earlier screenshots in `docs/changes/` and on
  `ci-screenshots` show the old text until the next build. No UI test matched on episode text.
- Not checked on a real Apple TV.

## Logging

None needed: this only changes text.
