#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"

swift build -c debug "$@"
binary_dir=$(swift build -c debug "$@" --show-bin-path)
app_output_dir=${LYRIS_APP_OUTPUT_DIR:-"$project_dir/.build/macOS"}
app_dir="$app_output_dir/Lyris.app"
contents_dir="$app_dir/Contents"

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

printf '%s\n' "$app_dir"
