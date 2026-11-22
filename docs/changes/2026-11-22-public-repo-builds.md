# The macOS build is free once the repository is public

## What changed
- `CLAUDE.md`: the macOS build (with its simulator screenshots) is now part of the checks for
  changes to screens, instead of "don't trigger it unless the owner asks".
- `.github/workflows/build.yml`: its header comment no longer says macOS minutes count ten times.
  The workflow itself is unchanged: it still runs only from the Actions tab or a `[build]` push.

## Why
The owner is making arc-apple public so the simulator screenshots can be taken freely: GitHub's
standard runners, macOS included, cost nothing on public repositories.

## Before going public
- The full history (all branches) was scanned for keys, tokens, private keys, signing files
  (`.p12`, `.p8`, `.mobileprovision`, certificates) and addresses. None found: the only addresses
  are example and test ones (192.168.1.x, 10.0.0.5, `arc.example.com`), and the TMDB key is only
  read from an Actions secret, which stays secret on a public repository.
- Session links in old PR descriptions were removed. Old commit messages still carry them.

## Merge after
The repository is switched to public. Until then the old rule (ten times the minutes) holds.

## Checks
Docs and a comment only; no code changed.

## Logging
None.
