# Arc for Apple TV

The Apple TV (tvOS) client for [Arc Media Server](https://github.com/arc-media-server/arc-media-server),
written in Swift and SwiftUI. It uses only Arc's stable `/api/v1`, like the Android app
([arc-android](https://github.com/arc-media-server/arc-android)).

Status: just started. Playback uses Apple's own player first, behind a small player interface,
so a different playback engine can be added later without rebuilding the app (decisions on
arc-media-server#80).

## Licence

AGPL-3.0-only, copyright "The Arc Media Server Authors". See [LICENSE](LICENSE).
