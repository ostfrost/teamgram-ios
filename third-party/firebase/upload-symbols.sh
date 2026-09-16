#!/bin/bash

set -euo pipefail

# --- begin runfiles.bash initialization v3 ---
set +e
runfiles_library_path="bazel_tools/tools/bash/runfiles/runfiles.bash"
source "${RUNFILES_DIR:-/dev/null}/${runfiles_library_path}" 2>/dev/null || \
  source "$(grep -sm1 "^${runfiles_library_path} " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -d ' ' -f 2-)" 2>/dev/null || \
  source "$0.runfiles/${runfiles_library_path}" 2>/dev/null || \
  source "$(grep -sm1 "^${runfiles_library_path} " "$0.runfiles_manifest" | cut -d ' ' -f 2-)" 2>/dev/null || \
  { echo >&2 "ERROR: cannot find Bazel runfiles library"; exit 1; }
set -e
# --- end runfiles.bash initialization v3 ---

upload_symbols="$(rlocation "firebase_crashlytics_binary/upload-symbols")"
if [[ -z "${upload_symbols}" || ! -x "${upload_symbols}" ]]; then
  echo >&2 "ERROR: cannot find Firebase Crashlytics upload-symbols"
  exit 1
fi

exec "${upload_symbols}" "$@"
