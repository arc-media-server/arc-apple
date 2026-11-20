# Batch 2: play queues and Shuffle, library filters, theme music, pre-roll videos (19 November)

The second batch of Apple TV parity items from arc-media-server#476. It's built on batch 1
(arc-apple#24), so one macOS build covers both. Each follows the Android app's version
(arc-android `docs/changes/2026-10-30-play-queues-server-name.md`, `2026-11-16-shuffle-season.md`,
`2026-11-17-library-filters.md`, `2026-11-17-theme-music.md`, `2026-11-17-preroll.md`).

## Play queues (Play Next, Add to Queue), Shuffle and Shuffle Season

- **ArcKit `PlayQueues`** (an actor, ported from Android's): `GET /capabilities` decides whether
  queues show at all (`play_queues` supported, available and allowed); calls run one at a time with
  the latest revision; a 409 (changed elsewhere) reads the queue again and retries once. An older
  Arc gets none of it. `Capabilities`, `PlayQueue`, `PlayQueueEntry` and the four routes are new.
- **Playing:** playing a title starts a new queue of it, as the web player does. The queue's next
  playable title becomes Up Next and plays on whatever Auto-Play is set to (it was queued on
  purpose). With nothing queued, Auto-Play's next episode is added to the end, so the queue stays a
  true record. A queue played to its end is deleted; Back keeps it. Not in Watch Together.
- **Play Next / Add to Queue:** in every card's menu and the title page's new ⋯ menu, for films,
  episodes and shows. A note at the top says what happened. With no queue yet they start one
  without playing.
- **Home's Queue row:** last on Home (the owner's choice on Android), while there's a queue: the
  title playing and what follows. Selecting a card plays on from that entry.
- **Shuffle:** a round button after Play on a show's page: its episodes on disk in a random order,
  as a new queue. **Shuffle Season** is in a season tab's menu. Both need more than one episode, and
  leave out the Not in This Order tab.
- **The title page's ⋯ menu:** Play Next, Add to Queue, Add to Playlist… and Rate… (batch 1's star
  button moves in here; five or six round icons were too many).

## Richer library filters

The Filters menu gains **Watch Status** (Watched, Not Started), **HDR**, **Video Format**, **Audio
Format** and **Audio Channels** (`watch_state`, `dynamic_range`, `video_codec`, `audio_codec`,
`audio_channels`). The media ones show only when the library has more than one value
(`libraries/{id}/facets`), or one is chosen; a chosen value stays listed. Unwatched Only and
Watch Status turn each other off, as Arc requires. The button counts the filters ("3 Filters"),
and Clear Filters keeps the sort. Names reuse the badges' (HEVC, DD+, TrueHD, 5.1).

## Theme music

On a film's or show's page with a tune (`theme_url`), it plays once per visit, fading in to a
quarter of the volume, and fades out when the page is left or anything opens over it (the player,
a trailer). Coming back from the player doesn't start it again. Not on episode pages. It follows
the profile's **Theme Music** (`theme_music`, on unless turned off), now a switch in Settings.
`ThemeMusic` (ArcTV/Player) is audio only, beside the playback engines.

## Pre-roll videos

A film started from the beginning plays the pre-roll videos chosen in Arc's Settings first
(`GET /items/{id}/preroll`), each through a cast link as extras are, with **Skip** focused at the
bottom right. Not when resuming, in Watch Together, or when the player moves on. A clip that fails
moves on; a list that fails or takes over 3 seconds plays the film without them. Back leaves the
player. `PrerollGate` wraps the player.

## Decisions

- **Queue row last, entries play on regardless of Auto-Play, Back keeps the queue:** as Android.
- **No queue editing yet** (Move Earlier/Later, Remove) on the Queue row; the web can. Next step.
- **A ⋯ menu on the title page,** as Plex's and Android's, rather than more round icons.
- **One change note for the batch,** as batch 1.

## Checks

- `swift test --package-path ArcKit` (Linux, Swift 6.2.1): 75 tests, 1 skipped (the live-server
  test), 0 failures. Before this batch: 69. New: queue start/Play Next with a 409 retry, a server
  without queues left alone, advance vs select, the new filters' parameters and exclusions, offered
  filter values, format names, theme music default, pre-roll list.
- Every edited and new tvOS file parses (`swiftc -parse`); every string key used exists.
- **Not compiled for tvOS:** the macOS build hasn't been run. Nothing tried in the simulator or on
  a real Apple TV: the queue's flow, focus in the ⋯ menu, theme music's fade and pre-roll playback
  all need seeing.

## Logging

- **Info:** how many pre-roll videos play; a queue edit retried after a change elsewhere.
- **Warnings** (error type only): a queue operation failing ("adding to the queue failed"…),
  shuffling failing, the pre-roll list failing or timing out, a pre-roll or its link failing.
- **Debug:** capabilities unavailable, a pre-roll skipped, theme music not playing, a queue action
  done, episodes shuffled.
- No ids, titles, addresses or tokens.
