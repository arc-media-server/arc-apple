# App Store exception

The owner decided arc-media-server#477 (21 November): Arc for Apple stays AGPL-3.0-only and adds an
additional permission under AGPL section 7 so the app can be published on the App Store and
TestFlight.

- `LICENSE-EXCEPTION.md`: the permission. It covers only The Arc Media Server Authors' own code,
  not third-party code (mpv, FFmpeg), and keeps the AGPL's source obligations. `LICENSE` is
  unchanged (the AGPL text verbatim).
- `README.md`, `CLAUDE.md` and `docs/plans/arc-engine.md` point to it.

Limits: the wording should be legally reviewed before the first App Store submission; this change
records no legal or store approval. No code, checks or logging affected.
