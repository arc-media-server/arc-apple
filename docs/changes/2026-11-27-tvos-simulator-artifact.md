# Apple TV simulator build artifact

The Build workflow publishes `arc-tvos-simulator`. Extract the GitHub artifact download
once, then upload the inner `Arc-tvos-simulator.zip` to a browser-hosted Apple TV simulator
such as VibeView. It contains an unsigned arm64 `Arc.app` built for the tvOS simulator.

The upload happens before the automated simulator walk. It needs no VibeView account
integration or signing credentials in GitHub. Start Arc against a reachable test server.
No device or playback verification is implied by the build.
