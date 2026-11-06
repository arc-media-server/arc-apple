# Watch Together on the TV apps (design plan)

Arc's Watch Together lets people in different places watch one title in step: everyone streams
their own copy and only the timeline is shared. The server and web have it (arc-media-server#341,
#344–#346; `docs/WATCH-TOGETHER-API.md` there). This plan is the TV design.

- **Native first:** the Apple TV app builds it first with tvOS's own controls and the app's glass
  look.
- **Then the others:** Android TV, Roku and LG/Samsung copy that design as closely as their
  platforms allow. The platform notes say where they can't.

## How it works for the viewer

1. **Invite.** On a film or episode, the card's context menu (hold Select) and the title page's
   More menu have **Watch Together…**. It opens the invite panel on the right-hand side, in the
   same glass as the player's Subtitles and Audio panel, so the title stays visible.
   - The panel is titled "Watch Together" with the title's name under it.
   - Below that is a list of the people this profile can invite (`GET /watch-together/people?item_id=`).
     Each row has the profile's picture (its initial on its colour), its name, "Friend" or nothing
     underneath, and a checkmark on the right when chosen. Select toggles a row.
   - Anyone who can't watch the title is dimmed, says "Can't watch this title" and can't be chosen.
   - **Done** is a prominent glass button at the bottom, disabled until someone is chosen.
     **Use a code instead** is a plain button beside it.
2. **Done** makes the room (`POST /watch-together/rooms`). The panel closes, and a small glass
   capsule says "Room ready: it's on Home under Watch Together" for a few seconds. Nothing starts
   playing.
3. **Home row.** A **Watch Together** row sits at the top of Home, above Continue Watching, only
   when there are rooms (`GET /watch-together/rooms`, refreshed on the events stream's
   `watch_together` hint).
   - Cards are wide, the same shape as Continue Watching: the title's background art with a people
     glyph and "Watch Together" in a small capsule at the top left (or "Watching now" when it's
     playing).
   - Under the card are the title (or the show and episode code), then "Hosted by Jo" or "You're
     hosting", then "Sam is here" or "Invited: Sam".
   - Select joins (`POST /watch-together/rooms/{id}/join`) and opens the player in the lobby.
   - The context menu has Join (Return if this device is already in it) and Decline (Cancel room
     for the host).
   - The last card in the row is **Join with a code**: a plain glass card with a keypad glyph that
     opens the code entry.
4. **Lobby.** The player opens paused on the title's first frame, dimmed, with a glass panel in the
   middle:
   - the title and "Watch Together";
   - **who's here**: picture, name, and Ready, Loading or Invited; the host has a crown glyph;
   - **for the host:** **Start** (prominent) and **Invite** (opens the invite panel to add people),
     plus "Or share code XXXX-XXXX" in small text. On a TV a code is easier to share than a link;
   - **for everyone else:** a spinner and "Waiting for Jo to start…";
   - **Leave**.

   Play/Pause on the remote while the lobby shows also starts the room, for the host.
5. **Watching.** The usual player:
   - Play/pause and seeking go to the room, and the player follows the room.
   - Small drifts are corrected by playing slightly faster or slower (97% or 103%), and big ones by
     jumping, as the web does.
   - Notices are a small glass capsule at the top centre for three seconds: "Paused by Sam",
     "Played by Sam", "Sam moved the room", "Waiting for Sam…".
   - The player's info and options panel gains a **Watch Together** section: who's there with their
     state, Leave, and End for everyone (host).
   - Playback speed is hidden in a room.
6. **Leaving.** Closing the player leaves the room. If the host ends the room, or the room is lost,
   the player carries on alone and says so in the capsule.
7. **Join with a code.** It's in Settings under Watch Together, and on the row's last card: eight
   characters on the platform's own keyboard, shown as XXXX-XXXX.

## Shared behaviour

All the apps use the same API and maths (the web's `lib/watch-together.ts` is the reference, with
no UI code in it):

- **Clock sync:** three `/time` samples, the lowest round trip wins, every minute.
- **Heartbeats** every 2 s, with the loaded generation.
- **Room stream:** `/watch-together/{id}/events`. It reconnects, and a 404 means the room is gone.
- **Drift:** under 0.5 s, nothing; up to 3 s, a rate change; beyond that, a seek.
- **Conflicts:** a 409 means adopt the returned room and retry once.
- **Late joiners:** they catch up by themselves and don't pause the room.

## Platform notes

| | Invite panel | Drift under 3 s | Home row live | Code keyboard |
|---|---|---|---|---|
| Apple TV | SwiftUI glass panel (`arcGlassPanel`) | `AVPlayer.rate` | events stream | tvOS keyboard |
| Android TV | Compose for TV side panel (as the player's options) | `ExoPlayer.setPlaybackSpeed` | events stream | system keyboard |
| Roku | the existing `OptionsPanel` on the right | the Video node can't change rate on HLS: seek past 1.5 s instead | events stream in a Task; if a stream can't stay open, refresh Home on return | `StandardKeyboardDialog` |
| LG / Samsung | a side panel in the app's own style (no blur on the LG C9: a dark translucent panel) | LG `<video>.playbackRate`; Samsung AVPlay `setSpeed` where allowed, else seek | EventSource | the TV's keyboard |

## Order of work

1. **Apple TV.**
   - ArcKit: the room client, the people and rooms calls, and the clock and drift maths, with tests.
   - Views: the Home row, the invite panel, the lobby, the player section and the capsules.
   - The stand-in Arc gains rooms, so the simulator walk-through screenshots each step.
2. **Android TV**, copying the Apple screenshots.
3. **LG/Samsung**, porting the web's `lib/watch-together.ts`.
4. **Roku**, last because its player can't change rate.

Each app's own to-do issue tracks its step.

## Checks

- Unit tests for the maths and the client in each app.
- The Apple walk-through screenshots.
- Two-device checks need real TVs and are marked (device) on the to-do lists. No device claims
  without evidence.
