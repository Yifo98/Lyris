# Lyris presentation modes reference

Updated: 2026-08-21
Platform: native macOS 13+
Coordinate unit: AppKit/SwiftUI points unless explicitly marked as pixels.

This document is the reusable parameter reference for Lyris presentation modes. Runtime `NSScreen` geometry remains authoritative; hard-coded values define layout behavior around the measured screen and camera housing rather than assuming every Mac has the same notch.

## Mode overview

| Mode | Product role | Window behavior | Close/fallback behavior |
|---|---|---|---|
| Mac Island (`topIsland`) | Default glance and control surface for a notched Mac | Non-activating top panel attached to the physical display edge | Expanded state collapses to compact; it remains the default fallback |
| Floating Bar (`floatingCard`) | Movable player for external or non-notched displays | Movable rounded panel with a persisted origin | Closing auxiliary windows leaves the floating bar active |
| Desktop Lyrics (`desktopLyrics`) | Complete lyrics reader and resizable player window | Standard activating AppKit window | Closing the reader automatically returns to compact Mac Island |

## 1. Compact Mac Island

### Runtime size

For a display with a camera housing:

```text
visual width  = measured camera width + (140 × 2)
visual height = measured safe-area top + 24
interaction host width  = visual width + (12 × 2)
interaction host height = visual height + 10
```

On the current 1512pt built-in display, the measured camera region is approximately 185 × 32pt:

```text
visual body      ≈ 465 × 56pt
interaction host ≈ 489 × 66pt
```

The interaction host includes transparent hover/click margins and must not be used as the visible silhouette size.

### Internal layout

| Parameter | Value | Purpose |
|---|---:|---|
| Left/right wing width | 140pt each | Balances metadata and effect around the camera housing |
| Lyric shelf width | 250pt | Centered V-shaped lyric region |
| Marquee outer viewport | 250pt | Matches the approved shelf without changing its silhouette |
| Protected lyric width | 216pt | Outer viewport minus two 17pt shoulder-safe insets |
| Edge fade | 17pt each side | Replaces hard clipping with a symmetric soft entrance/exit |
| Lyric shelf depth | 24pt | Readable compact lyric without becoming a second card |
| Lyric font | 11.5pt semibold | Compact glance readability |
| Shelf shoulder inset | 22pt | Controls the shallow V transition |
| Wing content safe offset | 15pt toward center | Keeps artwork/effect inside curved outer closures |
| Artwork | 24 × 24pt | Rounded 5pt continuous corner |
| Title allocation | 78pt | Single-line tail truncation |
| Effect mark | 66 × 10pt | Fine track-seeded waveform |
| Visible end-cap inset | 1pt | Protects antialiasing at host edges |
| Hover side expansion | 12pt each side | Invisible pointer target only |
| Hover depth | 10pt | Invisible pointer target below the visible body |

### Shape and interaction

- The upper outer closures and lower lyric shelf use the same shoulder slope and Bézier control-distance family.
- The surface stays hardware-black across skins; only text/effect accents follow the selected theme.
- Expansion triggers: hover, click, or hover + click.
- Hover dwell delay: configurable from 0 to 5 seconds.
- Expanded hold choices: 1.5 seconds, 3 seconds, 6 seconds, or persistent.
- The lock control keeps the island expanded until explicit unlock/collapse.

### Protected synchronized marquee

- The approved 250 × 24pt shell remains unchanged.
- Long lyrics travel inside a 216pt protected width, with a 17pt symmetric fade on both shoulders.
- The first and last 12% of the current lyric timeline remain still; for a typical three-second line this is approximately 0.35 seconds at each end.
- Travel is derived from the active lyric's playback progress and uses smoothstep easing. It has no independent marquee timer, so pause and seek cannot leave it drifting.
- Short lyrics remain centered and do not scroll.
- Responsive shelf expansion and a two-line compact state remain rejected because both destabilize the accepted silhouette.

## 2. Expanded Mac Island

### Runtime size

```text
preferred width = 1080pt
minimum width   = 900pt
available width = screen width - 64pt
resolved width  = clamped available width within 900...1080pt
body height     = 132pt + measured safe-area top
```

On the current built-in display, the result is approximately 1080 × 164pt.

### Layout

- Left identity region: 240pt.
- Center: lyric hierarchy and synchronized progress.
- Right controls: 190pt.
- Two soft vertical dividers: approximately 118pt high.
- Outer shape: top corner radius up to 14pt; bottom corner radius up to 28pt.
- Active playback effects use the highest surface refresh tier; idle state uses a reduced tier.
- Explicit collapse, lock, mode selection, settings, liked state, seek, transport, and a 174pt compact volume slider remain inside the same connected body.
- The volume row is shown only while the Mac Island is expanded; the compact hardware-attached state remains information-first.

## 3. Floating Bar

### Runtime size and placement

```text
minimum width = 620pt
maximum width = 820pt
resolved width = clamp(visible screen width - 64pt, 620...820pt)
height = 132pt
default top gap = 24pt below the visible-frame top
```

- Uses a continuous pill radius equal to half the panel height.
- The saved origin is restored only when at least half the panel remains visible.
- The panel is movable by its background.
- The expanded control cluster includes the same 174pt compact volume slider as the expanded Mac Island.
- On non-notched screens, compact fallback width is 480pt and height is 36pt; Lyris does not imitate a physical notch.

## 4. Desktop Lyrics

| Parameter | Value |
|---|---:|
| Initial content size | 1020 × 720pt |
| Minimum size | 860 × 620pt |
| Window type | Standard titled, closable, miniaturizable, resizable AppKit window |
| Placement | Centered below the top player without overlap |
| Persistence | Native frame autosave |

- The view renders the complete lyric document and follows the active line.
- Its full-width volume row shares the same playback capability and command path as the two lightweight modes.
- Hidden, minimized, or fully occluded windows pause their animation timelines.
- Closing this window while `desktopLyrics` is active persists `topIsland` and restores the compact island, preventing an interface-less state.

## 5. Settings window

| Parameter | Value |
|---|---:|
| Initial content size | 900 × 660pt |
| Minimum size | 760 × 520pt |
| Window level | Normal application level |
| Deactivation behavior | Remains open but may move behind another application |

The settings window is not an always-on-top utility panel. Its visual timelines pause when hidden, minimized, or fully occluded.

## Shared visual rules

- Base spacing rhythm: 24pt, with 12pt and 6pt subdivisions.
- Main radii: 20–28pt continuous corners.
- Accent: selected skin color; default direction is acid aurora green on near-black.
- Progress track: 4pt with explicit elapsed and total time where space permits.
- Compact state prioritizes physical integration and glance readability over control density.
- Expanded and desktop surfaces may expose full controls, context lines, and translation.
