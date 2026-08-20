# Lyris macOS Instructions

## Current phase

- The former MeloFloat overlay, Top Island, menu-bar lyrics, settings shell, brand assets, release packages, and demo-video projects were retired on 2026-08-17.
- Do not restore or incrementally restyle the deleted SwiftUI/AppKit presentation shell.
- The user approved the new product name `Lyris` and the design drop delivered on 2026-08-17.
- The approved visual truth consists of eight `image-gen-*.png` images from the `Lyris` design drop. The durable state mapping is recorded in `docs/design/lyris-design-contract.md`.
- The dark rounded-square acid-green ribbon icon is the production App icon. Do not restore the former MeloFloat waveform mark.
- `image-gen-5` defines the expanded top-player state, `image-gen-6` the main lyrics window, `image-gen-7` the menu-bar popover, and `image-gen-8` component tokens and states.
- The top surface follows Atoll's behavioral hierarchy without copying GPL code: compact state is a 32pt black glance wing attached to the left of the physical camera housing, with stacked song title and selected current lyric; hover/click expands one flat top-attached card and pointer exit collapses it. Do not restore the separate menu-bar lyric implementation or the old center-neck/lower-capsule contour.
- The current Lyris shell is a product implementation candidate, not a final release.

## Preserve as authoritative core

- Spotify PKCE, profile-scoped Keychain credentials, token refresh, polling, and liked-song semantics.
- Local Spotify playback, Web playback, Hybrid playback arbitration, monotonic playback clock, and stale-result isolation.
- LRCLIB lookup, typed lyric pipeline state, matching, LRC import/export, manual lyrics, cancellation, retry, and project-local cache.
- Translation endpoint validation, language decision, context-aware translation, user overrides, usage estimates, and secret redaction.
- `LyrisData/Lyrics`, user configuration, and Keychain data are user-owned; do not delete them during source or UI cleanup.

## Rebuild rules

- Native SwiftUI/AppKit remains the implementation technology. Do not reintroduce the deleted MeloFloat view or panel files.
- Separate playback/lyrics/translation state from macOS window and view code. A future shell consumes core state through a small, testable interface.
- Treat Atoll and Lyricify evidence as behavioral reference only. Atoll is GPL-3.0; do not copy its source, shapes, media adapters, or event coordinator.
- Use public macOS APIs and runtime `NSScreen` geometry for notch and multi-display behavior.
- New branding or visual deviations beyond the approved Lyris design drop require explicit user approval.
- Real Spotify artwork always wins in production. The synthetic `Northbound` artwork is QA-only and must never replace a real cover.
- Keep development output under `apple/Lyris/.build/`; never use `/private/tmp` for project artifacts.
- Never commit API keys, Client IDs, refresh tokens, cookies, personal lyrics, artwork caches, account screenshots, or private browsing data.

## Verification

- Run focused tests first, then `swift test` after core changes.
- The Lyris QA app must build with `scripts/build-qa-app.sh` before handoff.
- No commit, push, PR, release, or deployment without explicit user authorization.
