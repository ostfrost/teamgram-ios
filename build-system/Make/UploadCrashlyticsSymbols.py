"""Upload Bazel/Xcode dSYMs outside cached build actions (never inside a genrule)."""

import argparse
import hashlib
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import zipfile


REPOSITORY = Path(__file__).resolve().parents[2]


def has_dwarf_files(path):
    dwarf_directory = path / "Contents/Resources/DWARF"
    try:
        return any(candidate.is_file() for candidate in dwarf_directory.iterdir())
    except OSError:
        return False


def directory_symbols(directory):
    # rules_apple puts app symbols in <target>_dsyms/<bundle name>.app.dSYM,
    # while framework dSYMs are directly in bin/Telegram.
    candidates = list(directory.glob("*.dSYM")) + list(directory.glob("*_dsyms/*.dSYM"))
    return [path for path in candidates if has_dwarf_files(path)]


def find_symbols(paths, bazel_out=None):
    candidates = []
    if bazel_out:
        # Only this app's top-level products, not unrelated external repositories.
        for directory in Path(bazel_out).glob("*/bin/Telegram"):
            candidates.extend(directory_symbols(directory))
    for value in paths:
        path = Path(value).resolve()
        if not path.exists():
            raise ValueError("Symbol path does not exist: {}".format(path))
        if path.name.endswith((".dSYM", ".zip")):
            if path.suffix == ".zip" or has_dwarf_files(path):
                candidates.append(path)
        else:
            candidates.extend(directory_symbols(path))
    return sorted({path.resolve() for path in candidates})


def symbol_key(path):
    if path.suffix == ".zip":
        with zipfile.ZipFile(path) as archive:
            if not any(".dSYM/Contents/Resources/DWARF/" in name and not name.endswith("/")
                       for name in archive.namelist()):
                raise ValueError("Archive contains no dSYM DWARF files: {}".format(path))
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        return "zip-" + digest.hexdigest()
    result = subprocess.run(
        ["xcrun", "dwarfdump", "--uuid", str(path)],
        check=True, capture_output=True, text=True,
    )
    uuids = sorted(set(re.findall(r"UUID: ([0-9A-Fa-f-]{36})", result.stdout)))
    if not uuids:
        raise ValueError("No UUIDs in dSYM: {}".format(path))
    return "_".join(value.lower() for value in uuids)


def upload(args):
    if os.environ.get("AVATAR_CRASHLYTICS_UPLOAD") == "0" or os.environ.get("ACTION") == "indexbuild":
        print("Crashlytics: symbol upload explicitly skipped.")
        return
    plist = Path(args.google_service_plist).resolve()
    with plist.open("rb") as stream:
        config = plistlib.load(stream)
    if config.get("BUNDLE_ID") != "com.avatarmessenger.app" or not config.get("GOOGLE_APP_ID"):
        raise ValueError("Firebase config must identify com.avatarmessenger.app: {}".format(plist))
    symbols = find_symbols(args.dsym_path, args.bazel_out)
    if not symbols:
        message = "No app dSYMs found. Build with --apple_generate_dsym --output_groups=+dsyms."
        if args.allow_empty:
            # The Xcode aggregate hook also runs when building an individual library.
            print("warning: Crashlytics: " + message)
            return
        raise ValueError(message)
    app_key = hashlib.sha256(config["GOOGLE_APP_ID"].encode()).hexdigest()[:20]
    cache = Path(args.cache_dir) / app_key
    pending = [(path, cache / symbol_key(path)) for path in symbols]
    pending = [(path, stamp) for path, stamp in pending if args.force or not stamp.exists()]
    if not pending:
        print("Crashlytics: all {} dSYM(s) already uploaded.".format(len(symbols)))
        return
    command = [str(Path(args.bazel).resolve())]
    if args.bazel_user_root:
        command.append("--output_user_root=" + str(Path(args.bazel_user_root).resolve()))
    command += ["run", "//third-party/firebase:upload-symbols", "--",
                "--google-service-plist", str(plist), "--platform", "ios"]
    if args.debug:
        command.append("--debug")
    command.extend(str(path) for path, _ in pending)
    print("Crashlytics: uploading {} symbol bundle(s).".format(len(pending)), flush=True)
    subprocess.run(command, cwd=REPOSITORY, check=True)
    # Do not mark failures as uploaded: the next build must retry them.
    cache.mkdir(parents=True, exist_ok=True)
    for _, stamp in pending:
        stamp.touch()
    print("Crashlytics: symbol upload completed.")


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--dsym-path", action="append", default=[], help="dSYM, ZIP or directory of dSYMs; repeatable")
    result.add_argument("--bazel-out", help="Xcode's BAZEL_OUT; searches app products only in */bin/Telegram")
    result.add_argument("--google-service-plist", default=str(REPOSITORY / "avatar-module-ios/Sources/Resources/GoogleService-Info.plist"))
    result.add_argument("--bazel", default=str(REPOSITORY / "build-input/bazel-8.4.2-darwin-arm64"))
    result.add_argument("--bazel-user-root")
    result.add_argument("--cache-dir", default=str(REPOSITORY / "build-input/crashlytics-uploaded-symbols"))
    result.add_argument("--allow-empty", action="store_true", help="Warn instead of failing for non-app Xcode builds")
    result.add_argument("--force", action="store_true", help="Ignore successful-upload cache")
    result.add_argument("--debug", action="store_true")
    return result


if __name__ == "__main__":
    try:
        upload(parser().parse_args())
    except (OSError, ValueError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        # A failed upload must not fail the app build/archive: the binary is fine,
        # nothing is stamped as uploaded, so the next build retries, and dSYMs can
        # be uploaded later from the .xcarchive. Set AVATAR_CRASHLYTICS_STRICT=1
        # to make it fatal again (e.g. on CI).
        if os.environ.get("AVATAR_CRASHLYTICS_STRICT") == "1":
            print("error: Crashlytics symbol upload failed: {}".format(error), file=sys.stderr)
            sys.exit(1)
        print("warning: Crashlytics symbol upload failed (build continues): {}".format(error), file=sys.stderr)
        sys.exit(0)
