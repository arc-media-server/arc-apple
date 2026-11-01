# The sidebar's icons always show

## What changed

The places now sit in Arc's own sidebar instead of tvOS's adaptable one, following the owner's
reference screenshots. When it's shut, only the icons show down the left, straight on the page, with
the profile's picture at the top and a grey disc behind the place that's showing. Moving left onto
it (or Back from a place's first page) opens it. The icons stay exactly where they are while a tall
glass panel comes in behind them and the names fade in beside them, with the profile's name at the
top. Selecting the profile switches profile. The page behind dims. Moving up and down only highlights a place, and Select opens it and shuts the sidebar.
Coming into the sidebar always starts on the place that's showing. Back in the sidebar leaves the
app, as on tvOS's own sidebar.

Each place keeps its pages while another is showing, as the tab view did. A place is first built
when it's opened.

Moving the focus out of the sidebar after Select took some finding. tvOS won't move the focus to
"the page", only to a view it's told about: dropping it, or asking tvOS to decide again, left the
focus nowhere, so the next press went back into the sidebar and Back left the app. Select now
moves the focus to an invisible stop at the page's top left. The sidebar shuts, the next press
moves on into the page, and Back there opens the sidebar again. Up past the profile and down past
Settings keep the focus in the sidebar.

## Why

The owner (1 November) wants it to work as their reference screenshots show: tvOS 26's sidebar shrinks to a small
pill with no icons when shut, so you can't see where you are or what's there.

## Decisions

- The look follows the rest of the app: the focused row is white with black text, the place
  that's showing is in white and the rest are dimmed. There's no UI colour.
- Back on a place's first page opens the sidebar straight away. Plex first scrolls a page to its
  top, but Arc's pages are short and this keeps one press to the places.
- The sidebar doesn't scroll. A profile with a dozen libraries still fits on a 1080p screen. It
  would need scrolling past roughly 14 places.

## Limits

- Checked in the tvOS 26 simulator only (the walk-through's screenshots), not on an Apple TV.
- Right after Select nothing on the page looks focused until the next press, because the focus
  sits on the invisible stop. Pages could later name their own first focus instead.
- Search's keyboard is laid out by tvOS and starts under the icons.

## Logging

No change. This is layout and focus only, and library loading keeps its warning.
