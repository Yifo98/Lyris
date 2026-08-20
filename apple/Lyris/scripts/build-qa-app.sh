#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export LYRIS_APP_OUTPUT_DIR="$project_dir/.build/qa"

exec "$project_dir/scripts/build-debug-app.sh" "$@"
