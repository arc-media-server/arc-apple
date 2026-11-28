# Send logs on Apple TV

Settings sends recent Arc events to the current server when selected. Detailed logging adds debug
events for two hours. The journal stores fixed event codes only and clears with the device sign-in.
The Apple TV app does not offer crash uploads. MetricKit crash diagnostics are unavailable on tvOS.

The journal covers launch, profile selection, network failures and playback decisions/failures. The
upload uses the normal Bearer header and refuses redirects. The tvOS workflow runs ArcKit tests and
checks upload against the local stand-in. Physical Apple TV validation remains outstanding.

Server dependency: [Arc Media Server #508](https://github.com/arc-media-server/arc-media-server/pull/508).
