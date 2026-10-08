#!/bin/zsh
set -euo pipefail

project_root="${0:A:h}"
native_project="$project_root/apple/Lyris"
app_path="$native_project/.build/macOS/Lyris.app"

# SwiftPM owns incremental builds and the deployment target in Package.swift.
# The host OS may be newer than the installed SDK; it is not a deployment target.
(
    cd "$native_project"
    ./scripts/build-debug-app.sh --disable-sandbox
)

open "$app_path"
