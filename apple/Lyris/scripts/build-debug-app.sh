#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"

swift build -c debug "$@"
binary_dir=$(swift build -c debug "$@" --show-bin-path)
app_output_dir=${LYRIS_APP_OUTPUT_DIR:-"$project_dir/.build/macOS"}
app_dir="$app_output_dir/Lyris.app"
contents_dir="$app_dir/Contents"
stamp_path="$app_output_dir/.lyris-debug-inputs.sha256"

# Keep an unchanged signed bundle in place, while also detecting packaging and
# resource changes that SwiftPM does not track for this executable target.
input_hashes=$(shasum -a 256 \
    "$binary_dir/Lyris" \
    "$project_dir/scripts/build-debug-app.sh" \
    "$project_dir/Packaging/Info.plist" \
    "$project_dir/Packaging/Lyris.entitlements" \
    "$project_dir/Sources/Lyris/Resources/Brand/Lyris.icns" \
    "$project_dir/Sources/Lyris/Resources/Brand/LyrisAppIcon.png" \
    "$project_dir/Sources/Lyris/Resources/Demo/LyrisDemoArtwork.png")
input_hash=$(printf '%s\n' "$input_hashes" | shasum -a 256)
if [ -x "$contents_dir/MacOS/Lyris" ] \
    && [ -f "$stamp_path" ] \
    && [ "$(cat "$stamp_path")" = "$input_hash" ] \
    && codesign --verify --deep --strict "$app_dir" >/dev/null 2>&1; then
    printf '%s\n' "$app_dir"
    exit 0
fi

rm -rf "$app_dir"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources/Brand" "$contents_dir/Resources/Demo"
cp "$binary_dir/Lyris" "$contents_dir/MacOS/Lyris"
cp "$project_dir/Packaging/Info.plist" "$contents_dir/Info.plist"
cp "$project_dir/Sources/Lyris/Resources/Brand/Lyris.icns" "$contents_dir/Resources/Lyris.icns"
cp "$project_dir/Sources/Lyris/Resources/Brand/LyrisAppIcon.png" "$contents_dir/Resources/Brand/LyrisAppIcon.png"
cp "$project_dir/Sources/Lyris/Resources/Demo/LyrisDemoArtwork.png" "$contents_dir/Resources/Demo/LyrisDemoArtwork.png"
codesign \
    --force \
    --deep \
    --sign - \
    --entitlements "$project_dir/Packaging/Lyris.entitlements" \
    "$app_dir"
printf '%s\n' "$input_hash" > "$stamp_path"

printf '%s\n' "$app_dir"
