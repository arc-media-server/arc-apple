# Watch Together

The Apple TV app can watch a film or episode in step with other people through Arc's Watch Together
rooms (the server's docs/WATCH-TOGETHER-API.md). Everyone streams their own copy; only the
timeline is shared. This is the TV design the other apps copy (`docs/plans/watch-together.md`).

## What changed

- **Inviting:**
  - Watch Together… is in a title's context menu (hold Select), and is a round glass button on the
    title page.
  - It opens a glass panel down the right-hand side, like the player's options. It lists the
    people this profile may invite, each with their picture and name, and "Friend" or "Can't watch
    this title" under it.
  - Select ticks a person. **Done** makes the room; nothing plays yet, and a capsule says it's on
    Home. **Use a Code Instead** makes a room with a code and opens the lobby.
- **Home's Watch Together row:** above the other rows, while there are rooms.
  - Each card has the title's background and a "Watch Together" capsule (or "Watching now").
  - Under the card: "Hosted by Jo" or "You're hosting", and who's there or invited.
  - Select joins. Holding Select offers Join or Return, and Decline (or Cancel Room for the host).
  - The last card is **Join with a Code**, which is also in Settings.
- **Lobby:** a glass panel over the paused picture until the room first plays.
  - It shows who's here with a crown for the host, their state, and anyone invited.
  - The host has **Start** (or Play/Pause), **Invite** and **Leave**, and the code when it's their
    room.
  - Everyone else sees "Waiting for Jo to start…" and **Leave**.
  - Joining a room that's under way skips the lobby.
- **In the room:**
  - Play/Pause, skips, chapters and Skip Intro go to the room, and the player follows it.
  - A player out by up to 3 s plays at 97% or 103% until caught up; further out, it jumps.
  - "Paused by Sam", "Played by Sam" and "Sam moved the room" show in a glass capsule.
  - The options panel (swipe down) has a Watch Together section: who's there, Invite and End for
    Everyone (host), and Leave.
  - Up Next belongs to the host: it moves the room to the next episode, and everyone follows.
- **Leaving:** closing the player leaves the room. If the room ends or is lost, the player carries
  on alone and says so.
- **Engine:** `PlaybackEngine` gains `setRate`, for catching up. `AVPlayerEngine` keeps the rate
  through pauses.
- **ArcKit:** the room client and maths, with 10 tests (`WatchTogether.swift`).
  - The live stream is in the app (`WatchTogetherModel`). It splits lines by hand because
    `bytes.lines` drops the blank lines that end Server-Sent Events.
  - `Avatar` takes a name and colour, for people who aren't profiles on this device.

## Decisions (logged on arc-media-server#80)

- **The design source:** this app sets the TV design; the others copy its screenshots.
- **Code before link:** the host's lobby shows the code, not a link (easier to share from a TV).
- **Refreshing Home's row:** it refreshes when Home loads, and every 30 s while Home is showing.
  It will follow Arc's events stream once the app has live updates (on the to-do list).

## Checks

- `swift test --package-path ArcKit` on Linux (Swift 6.2.1): 46 tests, 1 skipped (the live
  server test), 0 failures.
- The stand-in Arc has two rooms (one hosted, one from Jo) and answers every room call. The
  walk-through adds:
  - 22: Home's Watch Together row;
  - 23 and 24: the host's and guest's lobbies;
  - 25 and 26: the invite panel, before and after choosing someone.
- Not checked: two Apple TVs in one room, drift on a real network, or a real Apple TV (device).

## Logging

- Info: joining or leaving a room, a room made (with how many were invited), and the room
  moving to the next episode.
- Warn: failed commands, joining or inviting failing, and a room's title not loading.
- Debug: a dropped stream (it reconnects) and refused retries.
- Never codes, names or addresses. Heartbeats log nothing.
