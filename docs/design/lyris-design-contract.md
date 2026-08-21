# Lyris design contract

Approved: 2026-08-17
Platform: native macOS 13+
Source: user-approved eight-image `Lyris` design drop produced with ChatGPT.

## State mapping

| Source image | Authority |
|---|---|
| `image-gen-1(4).png` | Primary dark App icon |
| `image-gen-2(3).png` | Optional light-context icon reference; not the default Dock icon |
| `image-gen-3(2).png` | Product lockup and spelling: `Lyris` |
| `image-gen-4(1).png` | Exploratory mark states; not all are production icons |
| `image-gen-5.png` | Persistent top player attached to a notched Mac display |
| `image-gen-6.png` | Main lyrics/player window |
| `image-gen-7.png` | Menu-bar popover |
| `image-gen-8.png` | Components, icons, progress, waveform, source chips, and 24px rhythm |

## Core tokens

- Dark mode first.
- Background: near-black with restrained wallpaper-reactive glass.
- Accent: acid aurora green, approximately `#9DFF38`.
- Primary text: warm white; secondary and inactive lyrics use stepped neutral opacity.
- Base spacing rhythm: 24pt, with 12pt and 6pt subdivisions.
- Main radii: 20–28pt continuous corners.
- Icons: SF Symbols with approximately 2pt optical stroke and round caps where available.
- Progress: 4pt track, green elapsed segment, explicit elapsed and total time.
- Waveform: fine vertical bars, track-seeded geometry, animated only while playing.

## Product surfaces

### Persistent top player

- One non-activating top-centered dynamic-island surface on the preferred notched screen.
- Compact state treats the physical camera housing as part of one continuous hardware-black silhouette. A restrained artwork/title wing sits on the left, a rhythm/effect wing sits on the right, and a centered shallow V-shaped shelf below the camera housing carries the current lyric.
- The compact lyric shelf uses a protected synchronized marquee: the 250 × 24pt shell stays fixed, while long text travels within a 216pt shoulder-safe region with symmetric 17pt fades and playback-progress-driven end holds.
- Hover or click expands the same surface into the full player; pointer exit collapses it through the same contour.
- The mock's wide player is the expanded state, not a literal always-visible screen-width instruction. On the current 1512pt Mac display, the measured camera housing is approximately 185 × 32pt; the compact visual body is approximately 465 × 56pt and its transparent interaction host is approximately 489 × 66pt. The expanded body is 1080 × 164pt on this display.
- Expanded state is one flat top-attached card, not a center neck joined to a lower capsule. Progress/time live in the left metadata column, liked state sits below artwork, the center is reserved for bilingual lyrics, and transport controls remain right-aligned.
- The physical camera housing is measured through public `NSScreen` safe-area APIs.
- Artwork, track/artist, current bilingual lyric, progress/time, compact waveform, shuffle, previous, play/pause, next, volume, and more. Volume remains hidden in the compact hardware-attached state and appears in the expanded Mac Island and Floating Bar.
- No automatic collapse into edge handles.

Detailed reusable geometry and transition parameters are maintained in [presentation-modes-reference.md](presentation-modes-reference.md).

### Main window

- Standard resizable activating macOS window with native traffic lights.
- Left column: artwork, track identity, liked state, progress, transport, volume, and secondary actions.
- Right column: five-line lyric context with current bilingual line emphasized.
- Page changes must not recreate the playback core.

### Menu-bar popover

- App icon status item opens a transient popover.
- Compact artwork header, progress/time, lyric context, transport, and open-main-window action.
- It does not inject content into or resize the macOS menu bar.

## Asset policy

- Production App icon is derived from the approved dark source and post-processed with a transparent outer canvas.
- Production artwork always comes from Spotify.
- `LyrisDemoArtwork.png` is a synthetic, text-free QA asset and is never a production fallback for a real track.
- The mock's wallpaper is contextual environment, not a bundled background image.
- Test lyrics are synthetic and must not reproduce copyrighted lyrics from the mock.

## Implementation boundary

The deleted MeloFloat UI and AppKit panel implementation are not a source. Spotify, playback, lyrics, translation, cache, and credential modules remain authoritative core behavior. Atoll and Lyricify remain clean-room behavioral evidence only.
