#!/bin/sh
set -eu

# Exercises the real launcher and packaging script without opening the app,
# accessing credentials, or depending on the host OS/SDK version.
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
mkdir -p "$project_dir/.build"
fixture=$(mktemp -d "$project_dir/.build/launcher-smoke.XXXXXX")
trap 'rm -rf "$fixture"' EXIT HUP INT TERM
repo="$fixture/Project With Spaces"
native="$repo/apple/Lyris"
mkdir -p "$native/scripts" "$native/Packaging" \
    "$native/Sources/Lyris/Resources/Brand" "$native/Sources/Lyris/Resources/Demo" \
    "$fixture/bin" "$fixture/binary"
cp "$project_dir/../../启动 Lyris.command" "$repo/启动 Lyris.command"
cp "$project_dir/scripts/build-debug-app.sh" "$native/scripts/"
for name in Info.plist Lyris.entitlements; do
    printf '%s\n' "$name" > "$native/Packaging/$name"
done
for name in Lyris.icns LyrisAppIcon.png; do
    printf '%s\n' "$name" > "$native/Sources/Lyris/Resources/Brand/$name"
done
printf 'demo\n' > "$native/Sources/Lyris/Resources/Demo/LyrisDemoArtwork.png"
printf '#!/bin/sh\nexit 0\n' > "$fixture/binary/Lyris"
chmod +x "$fixture/binary/Lyris"

cat > "$fixture/bin/swift" <<'SH'
#!/bin/sh
set -eu
for arg in "$@"; do
    case "$arg" in --triple|--sdk) exit 91 ;; esac
done
case " $* " in
    *' --show-bin-path '*) printf '%s\n' "$LYRIS_LAUNCHER_FIXTURE/binary" ;;
    *)
        printf 'build\n' >> "$LYRIS_LAUNCHER_FIXTURE/builds"
        [ ! -e "$LYRIS_LAUNCHER_FIXTURE/fail-build" ] || exit 92
        ;;
esac
SH
cat > "$fixture/bin/codesign" <<'SH'
#!/bin/sh
set -eu
case " $* " in
    *' --verify '*) exit 0 ;;
    *) printf 'sign\n' >> "$LYRIS_LAUNCHER_FIXTURE/signs" ;;
esac
SH
cat > "$fixture/bin/open" <<'SH'
#!/bin/sh
set -eu
[ -x "$1/Contents/MacOS/Lyris" ]
printf 'open\n' >> "$LYRIS_LAUNCHER_FIXTURE/opens"
SH
cat > "$fixture/bin/sw_vers" <<'SH'
#!/bin/sh
exit 93
SH
chmod +x "$fixture/bin/"*
export LYRIS_LAUNCHER_FIXTURE="$fixture"
export PATH="$fixture/bin:$PATH"
unset LYRIS_APP_OUTPUT_DIR

run_launcher() { /bin/zsh "$repo/启动 Lyris.command" >/dev/null; }
line_count() { wc -l < "$1" | tr -d ' '; }

run_launcher
[ "$(line_count "$fixture/signs")" = 1 ]
run_launcher
[ "$(line_count "$fixture/builds")" = 2 ]
[ "$(line_count "$fixture/signs")" = 1 ]

# A packaging change must rebuild even with an older mtime.
printf '\n<!-- changed -->\n' >> "$native/Packaging/Info.plist"
touch -t 200001010000 "$native/Packaging/Info.plist"
run_launcher
[ "$(line_count "$fixture/signs")" = 2 ]
cmp "$native/Packaging/Info.plist" "$native/.build/macOS/Lyris.app/Contents/Info.plist"

# Packaging-script changes participate in the content fingerprint too.
printf '\n# packaging revision\n' >> "$native/scripts/build-debug-app.sh"
run_launcher
[ "$(line_count "$fixture/signs")" = 3 ]

# Build errors must propagate instead of silently opening a stale binary.
touch "$fixture/fail-build"
if run_launcher; then
    printf 'Launcher ignored a build failure\n' >&2
    exit 1
fi
[ "$(line_count "$fixture/opens")" = 4 ]
printf 'Launcher smoke checks passed: incremental build, packaging, version target, failure propagation.\n'
