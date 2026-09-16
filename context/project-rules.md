1. Architecture & Code Structure
•	The avatar module architecture is MVVM.
•	UI must be written in SwiftUI.
•	Do not keep large SwiftUI screens in one file. Split views, view models, models, layout constants, palettes, and bridge containers into focused files.
•	Group screen files into clear feature subfolders, for example Root, Views, Models, and Support.
•	Move reusable UI pieces and bridge wrappers into Sources/Components and reuse them on new screens instead of duplicating.
•	Navigation inside the avatar module must be real stack-based navigation so swipe back works. The module must have its own independent root router.
•	iOS 17 support is mandatory; older iOS versions are outside the supported deployment range.
•	Use async/await and technologies available while supporting iOS 17.
2. UI, Resources & 3D Engine
•	Define colors through Assets with light/dark variants. Hex color initialization must accept strings in #002D31 format.
•	Do not manually branch on colorScheme == .dark.
•	Always account for VoiceOver/accessibility on screens and re-check labels, values, hints, and selected states when changing interactive UI.
•	Model lighting should be configured on the engine side so Android and iOS match.
•	Do not zoom a Metal/3D renderer with SwiftUI scaleEffect; use engine camera/framing when available.
•	Avatar model rotation must be controlled through the engine/bridge render controls. Do not fake rotation with SwiftUI gestures or Swift-only state.
•	Avoid names like Generated in public types and layers.
3. Bazel, Build & Verification
•	When creating new files, add them to the relevant project/build metadata (for Bazel/SPM targets verify the glob includes them, for Xcode add file reference).
•	After adding, moving, or deleting Swift files, regenerate Telegram/Telegram.xcodeproj with build-input/bazel-8.4.2-darwin-arm64 run //Telegram:Telegram_xcodeproj. Do not invoke //Telegram:Telegram_xcodeproj_raw directly.
•	Never report avatar module work as complete until the generated Telegram Xcode project has been regenerated and built successfully (e.g., using xcodebuild -project Telegram/Telegram.xcodeproj -scheme 'Avatar Messenger App').
•	Bazel Cache Maintenance: If Xcode reports "The bazel build failed" and logs show a missing rules_xcodeproj package, do not manually delete /Users/parafon/telegram-bazel-cache as it causes painful dependency rebuilds.
•	Instead, run avatar-module-ios/.avatar-local/scripts/restore-bazel-xcodeproj-cache.sh --apply --minimal --fast. Use --deep mode only if the minimal restore is not enough.
4. Engine & API Rules
•	avatar-engine must be used only inside avatar-module-ios and connected only through the CAvatarEngine bridge. The host app must not link Filament directly.
•	avatar-module-ios must store AvatarEngine.xcframework inside Vendor.
•	AvatarEngine.xcframework must be built with minimum deployment target iOS 17.0.
•	Implement the API client in layers inside the Swift Package; the API layer must be ready for SPM integration.
•	The authorization flow must handle authorized, sign_up_required, and password_required.
5. General Safety & Collaboration
•	Do not use hacky fixes, workaround-style implementations, or temporary code paths as a substitute for a proper fix.
•	Do not store or commit keys, secret plists, credentials, or concrete backend endpoints. Use placeholders in public module code.
•	STRICT GIT POLICY: Never execute or suggest executing git commit or git push commands. All git operations are strictly forbidden for the AI. The human developer retains exclusive control over version control.
•	When the human developer pushes code, it must be only to avatar-module-ios and teamgram-ios using the dev-avatar branch.