# Apple TV screenshot walk-through

The simulator walk now checks that Breaking Bad has focus before opening its page. Focus can
land on either side of that card when moving down to Recently Added. The Search walk moves
focus onto Apple's keyboard and waits for a recorded Dune result before capturing the results
screen. An unexpected focus position fails the walk with a specific message.

The screenshot stand-in resolves season poster paths through TMDB's season artwork endpoint
and falls back to the show's poster if the season has no suitable art. Without the workflow's
optional TMDB credential, the stand-in still uses generated placeholders. It logs only the
failure type if a season artwork lookup fails.

These changes affect the screenshot fixture and simulator walk. Real-device playback is
outside their scope.
