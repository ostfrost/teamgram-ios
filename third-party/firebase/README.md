# Firebase Crashlytics (Bazel / Xcode)

The app bundle ID is `com.avatarmessenger.app`. Its Firebase configuration is
`avatar-module-ios/Sources/Resources/GoogleService-Info.plist`, packaged in
`AvatarIntegrationBundle.bundle`. Do not use the old `com.avatarmessanger.app` app.

## Automatic symbols

- `.bazelrc` enables dSYM generation and requests the `dsyms` output group for
  both debug and release builds, including simulator builds.
- The generated Xcode project enables dSYMs in Debug/Release. Its Bazel post-build
  hook uploads app and embedded framework/extension symbols from `BAZEL_OUT`.
  Index-only builds are skipped. Regenerate with `//Telegram:Telegram_xcodeproj`
  after changing `Telegram/BUILD`; editing only the generated project is not durable.
- `Make.py build` and `scripts/lldb_build.sh` upload after successful app builds.
- `DeployToFirebase.py --dsyms …` uses the same uploader for existing release ZIPs.

`UploadCrashlyticsSymbols.py` validates dSYMs, calls the official Firebase
`upload-symbols` tool, and caches only successful uploads by Firebase app ID and
UUID (ZIPs by content hash). A failed upload exits nonzero and is retried on the
next invocation. Xcode builds of individual libraries with no app dSYM emit a
warning instead. Cache files live in ignored `build-input/crashlytics-uploaded-symbols`.

Plain `bazel build` produces dSYMs but intentionally does not perform network
writes inside cached Bazel actions. When invoking Bazel directly, follow the build
with:

```sh
python3 build-system/Make/UploadCrashlyticsSymbols.py --dsym-path bazel-bin/Telegram
```

The helper resolves symbol paths before starting Bazel, so its own tool build
cannot change which dSYMs are uploaded. Use `--force` to retry despite a successful
upload cache, or `--dsym-path /absolute/path/to/Telegram.DSYMs.zip` for an archive.
For intentional offline builds, set `AVATAR_CRASHLYTICS_UPLOAD=0`; these builds
still generate symbols, but you must upload them later.

## Missing symbols

Compare the UUID in Firebase's dSYMs tab to `xcrun dwarfdump --uuid path/to/app.dSYM`.
A dSYM from a different build cannot decode an old crash. Preserve the IPA and
dSYMs together for every distributed build. The upload tool sends symbols, not
the application binary.

The 2026-08-31 simulator test used UUID
`A82CCF5A-B80A-316D-9908-5D1A946F0277`; its dSYM was recovered from the exact
unstripped Bazel binary and accepted by Firebase. Never substitute symbols from a
new rebuild for that UUID.

Reference: https://firebase.google.com/docs/crashlytics/ios/get-deobfuscated-reports
