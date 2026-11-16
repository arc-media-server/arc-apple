# The A–Z bar in a library's Browse grid (15 November)

The second item from the feature-parity review. Getting to the S's in a large library meant
scrolling down from the top, a page at a time. The web and the Android TV app have a letter bar
for this, and Plex for Apple TV has one down the right of a library.

## What changed

- **The bar:** sorted by Title, a library's Browse grid has an A–Z bar down the right.
  - It shows only the letters that have titles, with "#" for digits, punctuation and other
    scripts.
  - The letters follow the list's order: Z to A when the sort is reversed.
  - The bar stays in place while the titles scroll. Moving right from the grid reaches it, and
    left goes back.
  - It follows the filters: with Unwatched or a genre chosen, it counts only what's shown.
- **Select on a letter:**
  - It loads the titles up to that letter's first title, and a page past it, if the grid hasn't
    reached them yet (up to 500 a request).
  - Then it scrolls there and moves the focus to that title.
- **Other sorts** (Date Added, Year…) show no bar, as on the web and Android.
- **The grid's width:** it loses none, so it still fits six posters a row. Its right margin
  shrinks to make room for the bar.
- **ArcKit:**
  - `/items` is asked for `letters=1` on a title-sorted grid's first page, and `ItemPage.letters`
    reads the counts (both already in the v1 contract).
  - `letterJumps(_:reversed:)` works out where each letter starts, as the web's and Android's
    `letterOffsets`.
  - `pagesToReach(_:have:total:page:)` plans the requests for a jump.
  - Four tests.

## Decisions

- **Only the letters that have titles,** as Android does. The web shows all 27 and dims the
  empty ones. On a TV, empty letters would be focus stops that do nothing.
- **"#" can come twice** in Arc's counts: before A for digits, after Z for other scripts. The bar
  shows it once, at its first place in the list.
- **Loading forwards** from what the grid has, rather than Android's grid of placeholders that
  loads any page on demand. This keeps the grid as it is. A jump near the end of a very large
  library makes a few requests: about six for 3,000 titles.

## Checks

- `swift test --package-path ArcKit` on Linux (Swift 6.2.1): 57 tests, 1 skipped (the live
  server test), 0 failures. Before this change: 53 tests, 1 skipped, 0 failures.
- The edited tvOS files parse (`swiftc -parse`), and `Localizable.strings` passes `plutil -lint`.
- **Not compiled for tvOS:** the macOS build hasn't been run. So the bar hasn't been seen in the
  simulator, and the walk-through doesn't cover it yet. The stand-in Arc doesn't answer
  `letters=1`, so the walk-through would show no bar until it learns to.
- Not checked on a real Apple TV. Still to check there:
  - where the bar sits beside the header;
  - moving between it and the grid;
  - how a jump to a far letter feels in a large library.

## Limits

- **While a far jump loads,** nothing on screen shows it's working. It's usually quick.
- **The landing:** the focus lands on the letter's first title once the grid has built it.
  If tvOS hasn't laid it out by then, the grid is scrolled there, but the focus may stay on the
  bar until you move left.

## Logging

- **Debug:**
  - a jump: `library <id>: jumped to a letter, <n> more titles in <ms> ms`;
  - `library <id>: a letter's titles didn't load` when the jump couldn't reach its title.
- **Warning:** a page that fails logs through the existing `loadPage` path
  (`library letter failed to load: <error type>`).
- The library's id is the number already used in the library page's logs. No titles, letters,
  addresses or tokens.
