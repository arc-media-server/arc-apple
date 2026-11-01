# The sidebar's icons always show (as Plozz's)

## What changed

The places now sit in Arc's own sidebar instead of tvOS's adaptable one. When it's shut, a slim
glass strip down the left shows each place's icon, with a faint disc behind the place that's
showing. Moving left onto it (or Back from a place's first page) opens it. The icons stay
exactly where they are while the glass widens and the names fade in beside them. The page behind
dims. Moving up and down only highlights a place, and Select opens it and shuts the sidebar.
Coming into the sidebar always starts on the place that's showing. Back in the sidebar leaves the
app, as on tvOS's own sidebar.

Each place keeps its pages while another is showing, as the tab view did. A place is first built
when it's opened.

## Why

The owner (1 November) wants it to work as Plozz's does: tvOS 26's sidebar shrinks to a small
pill with no icons when shut, so you can't see where you are or what's there.

## Decisions

- The look follows the rest of the app: the focused row is white with black text, the place
  that's showing is in white and the rest are dimmed. There's no UI colour.
- Back on a place's first page opens the sidebar straight away. Plex first scrolls a page to its
  top, but Arc's pages are short and this keeps one press to the places.
- The sidebar doesn't scroll. A profile with a dozen libraries still fits on a 1080p screen. It
  would need scrolling past roughly 14 places.

## Limits

Checked in the tvOS 26 simulator only (the walk-through's screenshots), not on an Apple TV.

## Logging

No change. This is layout and focus only, and library loading keeps its warning.
