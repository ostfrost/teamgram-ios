#!/bin/sh
set -eu

if [ "$#" -lt 1 ]; then
    echo "Missing raw rules_xcodeproj runner path." >&2
    exit 2
fi

RAW_XCODEPROJ_RUNNER="$1"
shift

WORKSPACE_PATH="${BUILD_WORKSPACE_DIRECTORY:-$(pwd)}"
GENERATED_PROJECT_PATH="$WORKSPACE_PATH/Telegram/Telegram.xcodeproj"
if [ -d "$GENERATED_PROJECT_PATH" ]; then
    chmod -R u+w "$GENERATED_PROJECT_PATH"
fi

"$RAW_XCODEPROJ_RUNNER" "$@"

python3 "$WORKSPACE_PATH/build-system/Make/ProjectGeneration.py" \
    --base-path "$WORKSPACE_PATH" \
    --xcodeproj-path "Telegram/Telegram.xcodeproj" \
    --target-name "Telegram"
