# macOS native rebuild boundary

Updated: 2026-08-17

## Current state

The former MeloFloat presentation shell has been deleted. The executable now mounts the approved Lyris main window, menu-bar popover, and physical-notch island while preserving the trusted playback, lyrics, translation, and authorization core.

## Trusted implementation

The retained source provides five tested capability clusters:

1. **Playback** — local Spotify source, Web playback, Hybrid arbitration, commands, capabilities, and monotonic clock.
2. **Spotify account** — PKCE, profile-scoped refresh tokens, Keychain storage, network recovery, polling, and liked-song synchronization.
3. **Lyrics** — LRCLIB, matching, typed pipeline state, LRC import/export, user lyrics, retries, cancellation, and disk cache.
4. **Translation** — endpoint policy, language decision, async cancellation, context-aware prompts, user overrides, usage estimation, and credential redaction.
5. **Persistence** — project-local non-secret data and Keychain-only secrets.

## Deliberate quarantine

`LyrisStore.swift`, `LyrisDomain.swift`, `LyrisDisplayPreferences.swift`, and `LyrisAdapters.swift` still contain some presentation-era orchestration alongside trusted behavior. They remain compiled because validated cancellation, authorization, and cache behavior currently crosses those files. The next refactor must extract small playback/lyrics/translation session interfaces before deleting the residual presentation state.

This is a migration seam. New presentation work should consume smaller session interfaces instead of expanding these orchestration types further.

## Next architecture decision

For the next architecture pass:

- define one observable application-session interface;
- split core behavior from macOS window adapters;
- define screen/notch geometry behind a public-AppKit adapter;
- specify independent presentation models for main player, lyrics, and settings;
- keep the approved Lyris name, Logo, design tokens, and information hierarchy as the visual contract.

Atoll and Lyricify remain behavioral evidence only. Their source code, shapes, private media integrations, and event coordinators must not be copied.
