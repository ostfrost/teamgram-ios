#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/AvatarIntegrationDerivedData}"
CLANG_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/avatarintegration-clang-cache}"

cd "$ROOT_DIR"

export HOME="${AVATAR_VERIFY_HOME:-/tmp}"
export CLANG_MODULE_CACHE_PATH="$CLANG_CACHE_PATH"

"$ROOT_DIR/Scripts/fetch-filament.sh"

xcodebuild \
  -scheme AvatarIntegration \
  -destination 'generic/platform=iOS Simulator' \
  -sdk iphonesimulator \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

swift test --filter AvatarServiceClientTests
