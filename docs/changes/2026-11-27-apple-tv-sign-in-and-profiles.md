# Apple TV: server, sign-in, profiles and PIN (the owner's 27 November list)

Part of the owner's 27 November list for the Apple TV app: the screens before Home match Android's.

## What changed

- **Server screen** matches Android's: one left-aligned column over Arc's soft glow; the address
  with Connect beside it; one line under them, which says it's connecting, what went wrong, or the
  port note; then the servers found on the network.
- **Sign-in screen** matches Android's: the numbered steps and buttons on the left, the code in
  large boxes on the right.
- **Profile picker** matches Android's: round avatars with no card behind them, a white ring and
  a slight grow on focus, a lock badge on the rim for a profile with a PIN, and the name
  underneath, grey until focused. Before, each profile sat on a grey card with a "Locked" line
  under its name.
- **PIN:** Arc's own PIN step replaces the system dialog, as the web's and Android's:
  - the profile's picture and name, "Enter your PIN" and four boxes, with the next box ringed in
    white;
  - a number pad beside them (focus starts on 5), because the Siri Remote has no number keys;
  - the keys and boxes are Liquid Glass, as the Profiles and Sign Out buttons are; the focused key
    is white with black text;
  - the fourth digit checks the PIN, as Plex does;
  - a wrong PIN shakes the boxes, empties them and says "Try again";
  - Back or Profiles returns to the profiles.

## Checks

- `swift test --package-path ArcKit`: all pass (1 skipped); nothing in ArcKit changed.
- `swiftc -parse` on every changed file; every `L()` key exists; `git diff --check` is clean.
- The owner tried the server, sign-in and profile screens in a tvOS simulator (VibeView).
- The stand-in server has no profile with a PIN, so the walk-through doesn't reach the PIN
  screen; it was checked by reading the code and the owner's simulator runs.
- Nothing was tried on a real Apple TV.

## Logging

A refused PIN logs at debug ("profile PIN refused"), with no PIN or profile in it. Nothing else
new.
