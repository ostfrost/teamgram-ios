#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/Vendor/Filament"
ARTIFACT_DIR="$VENDOR_DIR/Artifacts"
ARCHIVE_PATH="$ARTIFACT_DIR/filament-v1.71.2-ios.tgz"
EXPECTED_SHA256="5941dbd82f95a8959f173d399674da5e0fd2da9ffba0ad1b427ed201678bcce6"
URL="https://github.com/google/filament/releases/download/v1.71.2/filament-v1.71.2-ios.tgz"

mkdir -p "$ARTIFACT_DIR"

if [ ! -f "$ARCHIVE_PATH" ]; then
  curl -L "$URL" -o "$ARCHIVE_PATH"
fi

ACTUAL_SHA256="$(shasum -a 256 "$ARCHIVE_PATH" | awk '{print $1}')"
if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
  echo "Filament checksum mismatch." >&2
  echo "Expected: $EXPECTED_SHA256" >&2
  echo "Actual:   $ACTUAL_SHA256" >&2
  exit 1
fi

rm -rf "$ARTIFACT_DIR/filament"
tar -xzf "$ARCHIVE_PATH" -C "$ARTIFACT_DIR"

echo "Filament v1.71.2 is ready at $ARTIFACT_DIR/filament"
