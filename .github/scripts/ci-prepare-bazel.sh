#!/bin/sh
# Prepares a clean CI checkout for Bazel builds:
#  - downloads the pinned Bazel binary from versions.json (gitignored build-input/)
#  - generates build-input/configuration-repository (normally produced by Make.py)
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
cd "$ROOT_DIR"

BAZEL_SPEC="$(python3 -c 'import json; print(json.load(open("versions.json"))["bazel"])')"
BAZEL_VERSION="${BAZEL_SPEC%%:*}"
BAZEL_SHA256="${BAZEL_SPEC#*:}"
BAZEL_PATH="build-input/bazel-${BAZEL_VERSION}-darwin-arm64"

mkdir -p build-input
if [ ! -x "$BAZEL_PATH" ]; then
  curl -fsSL --retry 3 -o "$BAZEL_PATH" \
    "https://github.com/bazelbuild/bazel/releases/download/${BAZEL_VERSION}/bazel-${BAZEL_VERSION}-darwin-arm64"
fi
echo "${BAZEL_SHA256}  ${BAZEL_PATH}" | shasum -a 256 -c -
chmod +x "$BAZEL_PATH"

CONFIG_DIR="build-input/configuration-repository"
mkdir -p "$CONFIG_DIR/provisioning"
: > "$CONFIG_DIR/WORKSPACE"
: > "$CONFIG_DIR/BUILD"
printf 'module(\n    name = "build_configuration",\n)\n' > "$CONFIG_DIR/MODULE.bazel"
printf 'exports_files([\n])\n' > "$CONFIG_DIR/provisioning/BUILD"
cat > "$CONFIG_DIR/variables.bzl" <<VARS
telegram_bazel_path = "${ROOT_DIR}/${BAZEL_PATH}"
telegram_use_xcode_managed_codesigning = True
telegram_bundle_id = "${CI_BUNDLE_ID:-com.avatarmessenger.app}"
telegram_api_id = "${CI_API_ID:-0}"
telegram_api_hash = "${CI_API_HASH:-0}"
telegram_team_id = "${CI_TEAM_ID:-0000000000}"
telegram_provisioning_profile_name = ""
telegram_app_center_id = "0"
telegram_is_internal_build = "true"
telegram_is_appstore_build = "false"
telegram_appstore_id = "0"
telegram_app_specific_url_scheme = "tg2"
telegram_premium_iap_product_id = ""
telegram_aps_environment = "development"
telegram_enable_siri = False
telegram_enable_icloud = False
telegram_enable_watch = True
VARS

"$BAZEL_PATH" --version
