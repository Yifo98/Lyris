# Design QA — Free Resize + Dynamic Partitioned Ripple

Status: **PASS for the requested floating-capsule and expanded Mac Island scope.**

## Visual comparison

- Preferred source: `.scratch/top-island-qa/2026-07-26-resize-wave/reference-preferred-partition-wave.png`
- Rejected bar-wave regression: `.scratch/top-island-qa/2026-07-26-resize-wave/reference-rejected-bar-wave.png`
- Current implementation: `.scratch/top-island-qa/2026-07-26-resize-wave/implementation-resized-704x148.jpeg`
- Combined review input: `.scratch/top-island-qa/2026-07-26-resize-wave/reference-vs-implementation.jpg`
- Motion evidence:
  - `.scratch/top-island-qa/2026-07-26-resize-wave/dynamic-wave-frame-a.jpeg`
  - `.scratch/top-island-qa/2026-07-26-resize-wave/dynamic-wave-frame-b.jpeg`

The implementation restores the selected parallel-ribbon composition instead of the
later short-bar equalizer. Eight continuous lines share a broad waveform, while seeded
track geometry and live motion phase keep the surface from looking like a fixed drawing.
The elapsed section uses the linked blue/pink/purple gradient and glow; the remaining
section stays quiet and the playhead remains draggable.

The source and implementation were reviewed together at the same expanded-card state.
The implementation keeps the continuous rounded rim, left artwork/text zone, right
transport/wave zone, elapsed/total times, and unclipped outer shape. The implementation
intentionally omits the red annotation rectangle from the source screenshot.

## Resize interaction

The floating capsule now has an invisible 8-point native hit region on all four edges.
Corners combine their two adjoining edges, so the same surface supports:

- horizontal resize from the left or right edge;
- vertical resize from the top or bottom edge; and
- diagonal resize from any corner.

The compact Mac Island remains fixed to the detected physical camera housing. Its expanded
surface uses the same free resize interaction and re-centres against the physical top edge
after the drag. Floating-capsule and expanded-island sizes are persisted independently.

Allowed ranges:

- floating capsule base: `360 × 76` through `900 × 230`;
- expanded Mac Island content: `520 × 90` through `900 × 230`.

## Native regression found and resolved

A first live attempt used AppKit's `.resizable` style on the transparent borderless
`NSPanel`. macOS 26 crashed inside `-[NSWindow(NSWindowResizing) _resizeWithEvent:]`
when the lower-right corner was dragged. The final implementation removes that system
resize path and uses a project-owned edge tracker that updates the window frame directly.

Live Computer Use verification after that change:

- diagonal: `560 × 82` → `704 × 148`;
- horizontal only: `704 × 148` → `784 × 148`;
- vertical only: `784 × 148` → `784 × 194`;
- relaunch: restored at `784 × 194`;
- expanded Mac Island: resized to `784 × 194` while remaining centred at physical `Y = 0`;
- left and top edges: reduced the island to `704 × 157` while preserving top attachment.

## Motion verification

Two playing-state frames were captured 0.85 seconds apart. The waveform-only crop has a
non-empty full-width difference (`bbox 353 × 146`, mean absolute RGB difference
approximately `19.83 / 12.87 / 23.35`), confirming that the ribbons deform during
playback rather than merely advancing a static progress mask.

The motion is playback-state driven. Spotify does not expose the Mac system-audio
amplitude to this app, so this is a deterministic visual rhythm based on song identity,
playback progress, and a live motion phase—not a claim of microphone/audio sampling.

## Verification boundary

- `swift build`: pass.
- Project-local debug and QA app bundles: build and ad-hoc signing pass.
- Display-preferences integration harness: pass.
- Real macOS window drag, resize, restart persistence, top-edge attachment, and two-frame
  motion review: pass.
- `swift test`: still blocked by the current Command Line Tools environment reporting
  `no such module 'XCTest'`; this is not reported as a test pass.
- A physical second-display visual pass remains separate from this single-screen resize
  acceptance.

## 2026-07-26 — Expanded lyric density and direct Mac Island morph

Status: **PASS for the native expanded-card layout; cross-device playback remains a
separate account-connected device check.**

The latest density review used the user's reported empty lyric state and the rebuilt
native QA app in one combined image:

- Reported state: `.scratch/top-island-qa/2026-07-26-current/reference-density.png`
- Rebuilt native state: `.scratch/top-island-qa/2026-07-26-current/implementation-density.jpeg`
- Combined review input: `.scratch/top-island-qa/2026-07-26-current/comparison-density.jpg`

Visible corrections:

- short current lyrics now align from the artwork-side edge rather than centering inside
  the full text column;
- track title and artist share a compact metadata row;
- primary and translated type scale modestly with card height;
- identical source/target text is not repeated as two indistinguishable lines; compact
  single-language content uses a subdued next-line preview instead;
- tall resized cards use the available height for previous/current/next lyric context,
  while the right waveform keeps the selected fine parallel-ribbon treatment.

The Mac Island content crossfade now uses the same `0.34 s` timing curve as the attached
panel frame, with no secondary reveal delay. The display-preferences harness verifies the
single-stage timing contract. Static native screenshots verify the final connected card
state; they are not presented as frame-by-frame motion evidence.

## 2026-07-26 — Whole-card Mac Island regression

Status: **PASS for the rebuilt native expanded state.**

The reported regression was an unintended third state: the expanded Mac Island window
was active while its visible body still used the simplified lyric-and-wave composition.
The state transition now has only two visual destinations:

- idle: the physical camera housing plus the compact linked-rhythm strip;
- expanded: one connected player card containing artwork, metadata, bilingual lyric,
  transport controls, the single shuffle-mode control, settings, elapsed/total time, and
  the shared partitioned-ribbon waveform.

The controls remain inside the card body instead of being placed in the camera-housing
bridge. Switching between Floating Capsule and Mac Island collapses the old mode before
publishing the new one, preventing the former oversized intermediate composition from
being constructed or persisted.

Comparison material:

- User-confirmed reference: `.scratch/audit-2026-07-26-current/reference-expanded.png`
- Rebuilt native app: `.scratch/audit-2026-07-26-current/implementation-whole-card.jpeg`
- Combined review input: `.scratch/audit-2026-07-26-current/reference-vs-whole-card.png`

The combined input confirms that both states use the same connected silhouette and
left-information/right-control hierarchy. The QA bundle currently shows the music-note
fallback because the demo cover asset is absent; real Spotify artwork remains the primary
runtime artwork source.

Regression verification:

- `swift build`: pass.
- QA app bundle build and ad-hoc signing: pass.
- Display-preferences integration harness: pass, including the no-intermediate-capsule
  contract and Mac Island expanded geometry.
- Same-language translation integration harness: pass.
- Menu-bar full-text and playback-synchronized marquee harness: pass.
- Native macOS accessibility inspection: expanded card exposes shuffle, previous,
  play/pause, next, liked, lyric, mode-switch, and settings controls inside the connected
  card body.
- `swift test --filter HybridPlaybackCoordinatorTests`: blocked by the local Command Line
  Tools environment reporting `no such module 'XCTest'`; this is not counted as a pass.

## 2026-07-26 — Traditional Spotify metadata and blank menu-bar lyric regression

Status: **PASS for the reported `演员 · 薛之謙` runtime case.**

The real Spotify snapshot used Traditional Chinese artist metadata while LRCLIB indexed
the same artist as `薛之谦`. LRCLIB returns zero rows for the original spelling and valid
synced rows for the Simplified spelling. MeloFloat now:

- keeps the original Spotify spelling for display;
- retries the provider search with a Simplified-Chinese metadata variant;
- compares candidates through the same canonical form before accepting them;
- preserves a usable primary response if only the compatibility lookup fails.

The menu-bar presentation no longer becomes empty while lookup is pending or unsuccessful.
It shows the current pipeline status, then switches to the active lyric when lyrics arrive.
The floating surfaces also show one honest loading/failure status instead of duplicating
the artist as a fake lyric line.

Regression verification:

- matcher script-variant harness: pass;
- LRCLIB provider harness with an empty Traditional query and valid Simplified retry: pass;
- menu-bar fallback, same-language translation, full-line and playback-synchronized
  marquee harness: pass;
- project-local debug app build and ad-hoc signing: pass;
- real `.build/macOS/MeloFloat.app`: `演员 · 薛之謙` changed from `未找到歌词` to the
  synchronized lyric lines after relaunch.

## 2026-07-26 — Menu-bar suffix reveal and direct whole-card expansion

Status: **PASS for the reported `爱太深会让人疯狂的勇敢` timing and final Mac Island
composition.**

The cached `背叛 · 曹格` lyric starts at `180.42 s` and changes at `188.15 s`. At the
reported `185 s` playback moment, the old nearly-linear offset had advanced only about
63%, leaving `疯狂的勇敢` outside the 76-point lyric viewport. The revised progress-derived
ease-out advances the viewport beyond 82% at that same instant, while still reaching the
final offset only when the timed line itself ends.

The Mac Island no longer crossfades separate idle and expanded content layers. Its window,
connected notch shoulder, artwork/lyric zone, controls, and partitioned ribbon surface now
resolve directly into the same whole-card destination.

Visual comparison:

- User-confirmed whole-card reference:
  `apple/MeloFloatPrototype/.build/qa/latest-tail-island/reference-expanded.png`
- Rebuilt native expanded state:
  `apple/MeloFloatPrototype/.build/qa/latest-tail-island/actual-expanded.jpeg`
- Same-canvas comparison:
  `apple/MeloFloatPrototype/.build/qa/latest-tail-island/reference-vs-actual.png`

Verification:

- menu-bar timing regression harness: pass at the exact reported lyric timestamps;
- display-preferences / connected-island contract harness: pass;
- native debug app build and ad-hoc signing: pass;
- native accessibility inspection: the connected card exposes artwork/lyrics, shuffle,
  previous, play/pause, next, liked, lyric, mode switch, settings, and elapsed/total time;
- visual reference and rebuilt native state were reviewed together and retain the same
  connected-notch, whole-card hierarchy;
- focused `swift test` remains blocked by the active Command Line Tools environment
  reporting `no such module 'XCTest'`; the standalone integration harnesses are the
  passing regression evidence.
