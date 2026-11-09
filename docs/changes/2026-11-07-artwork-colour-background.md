# The title page's background in the artwork's four colours (7 November)

## What changed

- **The title page's background is a four-colour blend.** It takes four colours from the
  server's `GET /api/v1/items/{id}/artwork/palette`, one for each quarter of the backdrop, and
  blends them corner to corner across the screen. It uses a `MeshGradient`, which tvOS 18 has.
- **Episodes keep the colours.** When the artwork slides away for a show's episodes, the blend
  is what's left behind them. That's the reference design's look, where the episode screen keeps
  the artwork's mix of colours rather than one flat wash.
- **The colours are toned down** (`RGB.toned()` in ArcKit, with tests). The hue stays, but
  saturation is at most 0.55 and brightness sits between 0.12 and 0.30, so white text stays
  readable. They fade in over 0.8 s once they arrive.
- **The artwork fades into the blend** at the bottom and the left. It uses masks rather than a
  dark layer on top, so the colours show through under the words.
- **Episodes use their show's colours** when the episode has no backdrop of its own.
- **The app's background is a soft dark grey** (#1C1D21), close to the reference's dark look, in
  place of near-black. Pages without artwork get a gentle grey blend of the same kind. The
  surface tokens moved up to match.
- **The app's own average-colour code is gone.** The server's colours replace it, so the TV no
  longer works out colours itself.

## Why the server's colours

The server already works out and keeps these four colours for apps. Using them means:
- the TV doesn't decode images to find colours;
- the Roku, Android and LG/Samsung apps can show the same colours later from the same answer.

## Walk-through

The stand-in server answers the palette request. It shrinks the picture it serves to 2x2 with
macOS's `sips` and reads one colour for each quarter, so the screenshots show real artwork
colours. If it can't, it answers "unavailable", as Arc does.

## Limits

- An older server without the palette endpoint, or a title without artwork, shows the grey
  blend.
- The blend runs top left to bottom right only. It doesn't drift or move.
- Not checked on a real Apple TV yet.

## Logging

Nothing new. A palette request that fails goes through `ArcAPI`'s existing failure logging, and
the page keeps the grey blend.
