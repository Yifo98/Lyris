# Lyris Design QA

This document records the durable visual and interaction acceptance criteria for the current native macOS implementation. Temporary build products, local screenshots, user-specific paths, and superseded MeloFloat experiments are intentionally excluded.

## Authoritative references

- [Lyris design contract](docs/design/lyris-design-contract.md)
- [Dynamic Island screenshot](docs/assets/screenshots/lyris-dynamic-island.png)
- [Desktop lyrics screenshot](docs/assets/screenshots/lyris-desktop-lyrics.png)
- [Settings screenshot](docs/assets/screenshots/lyris-settings.png)

The screenshots establish hierarchy, density, tone, and interaction intent. They are product evidence rather than pixel-perfect Windows layouts.

## Accepted product surfaces

### Compact Dynamic Island

- Uses the physical Mac camera housing as part of one continuous deep-black silhouette.
- Keeps album artwork and title inside the curved left wing.
- Keeps the effect mark inside the right wing without colliding with menu-bar items.
- Uses the centered lower V-shaped shelf for the current lyric.
- Displays only the current original line or its real translation; it never previews the next line as a fake translation.
- Supports configured hover dwell and click-to-expand behavior.
- Remains visually hardware-black across interface skins.

### Expanded Dynamic Island

- Expands from the compact surface rather than appearing as an unrelated floating capsule.
- Keeps artwork and metadata on the left, lyrics in the center, and playback controls on the right.
- Uses subdued particles and interwoven light-flow curves behind content.
- Keeps effect contrast below lyric and control contrast.
- Supports explicit collapse, persistent lock, seek, playback, liked state, mode selection, and settings access.

### Desktop lyrics

- Preserves the complete lyric document rather than truncating it to a small local window.
- Automatically follows the active line without stealing focus.
- Keeps translation and original text visually distinguishable.
- Restores window position and size through normal AppKit window persistence.
- Pauses visual timelines while hidden, minimized, or fully occluded.

### Floating bar and external displays

- Uses a centered movable rounded bar on displays without a camera housing.
- Does not imitate a physical notch on an external display.
- Keeps top-island, floating-bar, and desktop-lyrics modes mutually coherent during switching.

### Settings

- Uses the selected interface skin and linked-effect language without reducing readability.
- Never displays API keys or Spotify refresh credentials.
- Client ID and API-key fields default to concealed presentation.
- Font search operates on one cached system catalog and refreshes only after importing a font.
- Hidden settings windows do not keep their animation timelines running.

## Motion and performance contract

- Each visible surface owns only the animation work it needs.
- Hidden surfaces must pause their `TimelineView` schedules.
- The main lyrics view is created lazily when first opened.
- Settings use a lower update rate than the actively playing expanded island.
- Paused and idle surfaces use a reduced update rate while retaining subtle ambience.
- Track-seeded curves and particles stay deterministic enough for stable QA while still moving visibly.

Latest verified checkpoint on the current Apple Silicon Mac:

| Scenario | CPU | Memory |
|---|---:|---:|
| Compact idle island | approximately 0.4–0.5% | approximately 74 MB |
| Expanded playing island | approximately 6.5% | approximately 103 MB |
| Settings visible | approximately 19–23% | approximately 252–281 MB |

These figures are regression anchors, not universal hardware guarantees. A new visual effect must be remeasured on the running Release build before acceptance.

## Playback and lyric correctness

- All surfaces consume the same playback snapshot and monotonic clock.
- Positive lyric calibration makes lyrics appear later; negative calibration makes them appear earlier.
- Rapid track changes cannot let stale lyrics or artwork replace the current track.
- LRCLIB retrieval works without Spotify account authorization or a translation API key.
- Simplified/Traditional metadata, parenthesized collaborators, and common stage-name aliases are normalized before conservative matching.
- Translation failure cannot suppress usable original lyrics.

## Privacy and release boundary

- Production Spotify artwork always wins; synthetic artwork is QA-only.
- API keys and Spotify refresh tokens remain in macOS Keychain.
- Release archives must not contain `LyrisData`, caches, cookies, logs, credentials, account screenshots, or machine-specific absolute paths.
- The current public preview is ad-hoc signed and not Apple-notarized.
- GitHub Release descriptions contain update and feature notes only; durable homepage screenshots remain in the repository README.

## Verification commands

Run focused checks before the full package suite:

```sh
swift test --package-path apple/Lyris --filter LyrisPresentationTests
swift test --package-path apple/Lyris
apple/Lyris/scripts/build-qa-app.sh
apple/Lyris/scripts/build-release-app.sh
```

For performance changes, validate the running Release process with repeated CPU/memory samples and a main-thread sample. Passing unit tests alone is not visual or performance acceptance.

## Current checkpoint

- Shared progress and volume controls use explicit drag gestures instead of a nearly transparent native slider.
- Expanded Island seek moved from 100% to 43% and volume from 50% to 24% in the isolated live QA app.
- Floating Bar now uses the selected Option 1 “Floating Deck”: fixed 28pt corners, a content-first upper tier, and a 58pt shared control rail.
- Desktop Lyrics mouse drag moved seek from 43% to 83% in the isolated live QA app.
- The menu-bar popover includes the shared volume control and no longer instantiates the native slider responsible for the blue focus ring.
- Expanded Mac Island content now begins below the measured physical menu-bar/camera safe band; the right control cluster is visibly separated from system status items.
- The menu-bar popover now gives the lyric document the flexible main region. Progress and volume share one compact bottom control band; live QA changed progress from 47% to 77% and volume from 50% to 17%.
- Floating Deck live QA moved progress to 70% and volume to 30%; its v2 size keys prevent the rejected oversized capsule dimensions from restoring.
- Full package suite: 265 tests, 0 failures.
- Release and QA app bundles build successfully.
- Code signature verification passes for the ad-hoc preview bundle.
- Public source and Release asset are privacy-scanned before publication.

## Floating Deck Option 1 design QA — 2026-08-22

- Selected reference: `~/.codex/generated_images/01a017a0-5bb3-7891-920a-1eb330245a0c/exec-186317e5-ab1b-4db3-b28c-e83e1a341136.png`.
- Live implementation: `docs/qa/floating-deck-option1-final-2026-08-22.jpeg`.
- Same-width comparison: `docs/qa/floating-deck-option1-comparison-2026-08-22.png`.
- P0: none. The full player hierarchy and all core controls are present.
- P1: none. The implementation uses the selected fixed-radius two-tier structure instead of a height-derived pill.
- P2: none. Identity, lyric stage, transport, waveform, progress/time, volume, and utilities preserve the selected visual order and proportions.
- P3: the live 980 × 220pt surface is slightly flatter than the concept crop after same-width scaling; this is an intentional native-screen adaptation and does not break hierarchy.

final result: passed
