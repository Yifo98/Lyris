#!/bin/zsh
set -euo pipefail

project_root="${0:A:h}"
native_project="$project_root/apple/Lyris"
app_path="$native_project/.build/macOS/Lyris.app"
app_binary="$app_path/Contents/MacOS/Lyris"

needs_build=false
if [[ ! -x "$app_binary" ]]; then
    needs_build=true
elif find \
    "$native_project/Sources" \
    "$native_project/Packaging" \
    "$native_project/Package.swift" \
    -type f -newer "$app_binary" -print -quit | grep -q .; then
    needs_build=true
fi

if [[ "$needs_build" == true ]]; then
    sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
    deployment_version="$(sw_vers -productVersion | awk -F. '{ print $1 "." $2 }')"
    architecture="$(uname -m)"
    (
        cd "$native_project"
        ./scripts/build-debug-app.sh \
            --disable-sandbox \
            --triple "${architecture}-apple-macosx${deployment_version}" \
            --sdk "$sdk_path"
    )
fi

open "$app_path"
