# Player controls closer to the system player

Apple's guidance for custom players is to follow the system player's interface and behaviour, so
people's habits carry over. Following it:

- Playback, Audio and Subtitles open tvOS's own menus rather than Arc's panel. Choices are ticked.
  Playback holds Zoom Mode, Playback Speed (not in a Watch Together room), Quality and Version,
  each a submenu showing its current value. Back closes a menu.
- Only the bottom of the picture is shaded behind the controls, as the system player's. The
  whole picture no longer dims.
- The timeline is 12 points, with a taller marker. Subtitles move to the top of the screen while
  a card is up.

The player doesn't hide the controls while one of these menus is open. A menu holds the focus,
which the screen can't see, so "the controls are active but nothing on this screen has the
focus" stands for "a menu is open".

Not built yet. The next build's walk-through also takes a screenshot of the Subtitles menu open.

## Now Playing and the system's media commands

`NowPlaying` (ArcTV/Player) tells tvOS what's playing: the title, the show and the episode number,
the card's wide picture (loaded with the sign-in), the length, the position and whether it's
playing. tvOS shows it in Control Center and on the Now Playing screen. The system's play, pause,
play/pause, skip 10 seconds and seek commands go to the player, so Control Center, the iPhone
remote, Siri and AirPods controls work. In a Watch Together room they go to the room, as the
remote's do. tvOS keeps the clock running itself, so it is only told again when playback starts
or stops, after a jump, and when the length becomes known. Apple's `MPNowPlayingSession` needs
Apple's own player, so the default centres are used for both engines.

None of this can be checked in the simulator walk-through. It needs a real Apple TV with Control
Center or the iPhone remote.
