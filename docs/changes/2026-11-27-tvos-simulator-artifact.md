# Apple TV simulator build artifact

The Build workflow publishes `arc-tvos-simulator`. Extract the GitHub artifact download
once, then upload the inner `Arc-tvos-simulator.zip` to a browser-hosted Apple TV simulator
such as VibeView. It contains an unsigned arm64 `Arc.app` built for the tvOS simulator.

The upload happens before the automated simulator walk. It needs no VibeView account
integration or signing credentials in GitHub. Start Arc against a reachable test server.
No device or playback verification is implied by the build.

Fix (Claude): the first run (#39) built the simulator app but stopped at the architecture
check, because `lipo` takes the file before `-verify_arch`. The check now reads
`xcrun lipo "$APP/Arc" -verify_arch arm64`. Each Build run takes about a minute longer, since
the app is built a second time for the simulator.
