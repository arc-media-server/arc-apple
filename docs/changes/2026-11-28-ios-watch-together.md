# Watch Together on iPhone and iPad

The next item on the iPhone and iPad list (arc-apple#2): Watch Together, as the Apple TV has it.
The room itself (joining, the live stream, heartbeats, the clock and keeping in step) is the Apple
TV's `WatchTogetherModel`, now shared by both apps; only the screens are new.

## What changed

- **Home:** Watch Together's row sits under Continue Watching (or the first row) while there are
  rooms, as on the Apple TV: a card per room with the title's picture, who's hosting and who's
  there, then a Join with a Code card. A tap joins (or returns to) a room; touching and holding
  offers Join and Decline (Cancel Room for the host). The row follows Arc's live updates.
- **Inviting:** a film's or episode's menu (a card held, or the title page's menu) has Watch
  Together…. It opens a sheet listing who to invite, with Done to make the room and Use a Code
  Instead.
- **Joining with a code:** from the row's last card, or Settings › Watch Together. It's a short
  form with an eight-character code field.
- **The player in a room:**
  - Until the room first plays, a lobby panel sits over the paused picture. The host has Start,
    Invite and Leave, and the code to share. Guests see "Waiting for … to start".
  - Once the room plays, a Watch Together button joins the top bar. It opens the room's sheet:
    who's here and their state, Invite, Leave, and End for Everyone for the host.
  - Play, pause, the ±10 s buttons, double taps, the timeline and Control Center go to the room,
    and the player follows the room: drift is corrected by playing a little faster or slower, or
    by jumping when it's far out.
  - Notices such as "Paused by Sam" show at the top.
  - Speed and Play from Beginning are hidden in a room, because the room sets them. The play
    queue isn't touched, as on the Apple TV.
  - The host's Up Next moves the whole room on.
  - Closing the player leaves the room; the others carry on.
- The Apple TV app is unchanged: `TitleActions` no longer keeps the Watch Together item to tvOS.

## Decisions

- **The same room model as the Apple TV, and the same words.** Each screen follows iOS:
  - sheets for inviting and the code;
  - a list with ticks for choosing people;
  - a glass panel for the lobby.
  The alternative, a second copy of the room logic, is what the shared rules say not to do.
- **The room's controls are behind a button in the player's top bar, not a tab.** On the Apple TV
  they're one of the player's tabs. The iPhone player has no tabs, and a sheet keeps the picture
  in view while it's open.
- **Settings closes before a room's player opens**, and so does the code sheet. iOS shows one
  presentation at a time, so joining from Settings would otherwise open no player.

## Checks

- The macOS build and the iPhone simulator walk-through run on this PR's `[build]` run:
  - Home's Watch Together row (m18);
  - the host's lobby (m19);
  - the invite sheet (m20).
  The stand-in has a room this profile hosts and one it was invited to.
- Not tried:
  - two devices in one room;
  - a guest's lobby on iPhone;
  - joining with a code;
  - the iPad layout;
  - anything on a real iPhone or iPad.

## Limits

- Watch Together's `started` field (arc-media-server#487) isn't read yet. As on the Apple TV, the
  lobby is inferred from the room's state and position.

## Logging

The room model's existing records, shared with the Apple TV:
- joining and leaving;
- rooms made;
- failed commands, as warnings;
- dropped streams, at debug.

The new screens log a warning, with the error type only, when any of these fail:
- joining;
- inviting;
- loading the people to invite;
- making a room with a code.

They never log codes or names.
