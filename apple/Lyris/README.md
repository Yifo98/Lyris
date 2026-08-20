# Lyris native macOS workspace

This Swift package compiles the preserved Spotify, playback, lyrics, translation, cache, and credential core behind the new Lyris SwiftUI/AppKit shell.

The previous MeloFloat presentation was intentionally removed. Lyris implements its top player, lyrics window, menu-bar popover, components, and branding from the approved 2026-08-17 design drop.

```bash
swift test
./scripts/build-qa-app.sh
open .build/qa/Lyris.app
```

Production artwork comes from Spotify. `LyrisDemoArtwork.png` is synthetic and only used by the `--demo` visual-QA route.
