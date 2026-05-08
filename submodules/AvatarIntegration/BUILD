load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load(
    "@build_bazel_rules_apple//apple:resources.bzl",
    "apple_resource_bundle",
)
load("//build-system/bazel-utils:plist_fragment.bzl",
    "plist_fragment",
)

filegroup(
    name = "AvatarIntegrationModelResources",
    srcs = [
        "Sources/Resources/Models/avatar-model.glb",
    ],
    visibility = ["//visibility:public"],
)

filegroup(
    name = "AvatarIntegrationAssetResources",
    srcs = glob([
        "Sources/Resources/Assets.xcassets/**",
    ]),
    visibility = ["//visibility:public"],
)

plist_fragment(
    name = "AvatarIntegrationBundleInfoPlist",
    extension = "plist",
    template =
    """
    <key>CFBundleIdentifier</key>
    <string>org.telegram.AvatarIntegration</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleName</key>
    <string>AvatarIntegration</string>
    """
)

apple_resource_bundle(
    name = "AvatarIntegrationBundle",
    infoplists = [
        ":AvatarIntegrationBundleInfoPlist",
    ],
    resources = [
        ":AvatarIntegrationAssetResources",
        ":AvatarIntegrationModelResources",
    ],
)

cc_library(
    name = "FilamentLibDevice",
    srcs = glob([
        "Vendor/Filament/Artifacts/filament/lib/universal/*.a",
    ], exclude = [
        "Vendor/Filament/Artifacts/filament/lib/universal/libuberarchive.a",
    ]),
    visibility = ["//visibility:public"],
)

cc_library(
    name = "FilamentLibSimulatorArm64",
    srcs = glob([
        "Vendor/Filament/Artifacts/filament-ios-sim-arm64/lib/arm64/*.a",
    ], exclude = [
        "Vendor/Filament/Artifacts/filament-ios-sim-arm64/lib/arm64/libuberarchive.a",
    ]),
    visibility = ["//visibility:public"],
)

cc_library(
    name = "FilamentUberArchiveDevice",
    srcs = [
        "Vendor/Filament/Artifacts/filament/lib/universal/libuberarchive.a",
    ],
    alwayslink = True,
    visibility = ["//visibility:public"],
)

cc_library(
    name = "FilamentUberArchiveSimulatorArm64",
    srcs = [
        "Vendor/Filament/Artifacts/filament-ios-sim-arm64/lib/arm64/libuberarchive.a",
    ],
    alwayslink = True,
    visibility = ["//visibility:public"],
)

objc_library(
    name = "AvatarEngineBridge",
    module_name = "AvatarEngineBridge",
    enable_modules = True,
    srcs = [
        "Sources/Bridge/AvatarEngineBridge.mm",
        "Sources/Bridge/AvatarNativeEngineAdapter.h",
        "Sources/Bridge/AvatarNativeEngineAdapter.mm",
    ],
    hdrs = [
        "PublicHeaders/AvatarEngineBridge/AvatarEngineBridge.h",
    ],
    copts = [
        "-Wno-error",
        "-std=c++17",
    ],
    includes = [
        "PublicHeaders",
        "Vendor/Filament/Artifacts/filament/include",
        "Vendor/Filament/Artifacts/filament-ios-sim-arm64/include",
    ],
    deps = select({
        "//build-system:ios_sim_arm64": [
            ":FilamentLibSimulatorArm64",
            ":FilamentUberArchiveSimulatorArm64",
        ],
        "//conditions:default": [
            ":FilamentLibDevice",
            ":FilamentUberArchiveDevice",
        ],
    }),
    sdk_frameworks = [
        "CoreGraphics",
        "CoreVideo",
        "Foundation",
        "OpenGLES",
        "Metal",
        "QuartzCore",
        "UIKit",
    ],
    sdk_dylibs = [
        "c++",
    ],
    visibility = ["//visibility:public"],
)

swift_library(
    name = "AvatarServiceAPI",
    module_name = "AvatarServiceAPI",
    srcs = glob([
        "Sources/AvatarServiceAPI/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    visibility = ["//visibility:public"],
)

swift_library(
    name = "AvatarAuthClient",
    module_name = "AvatarAuthClient",
    srcs = glob([
        "Sources/AvatarAuthClient/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        ":AvatarServiceAPI",
    ],
    visibility = ["//visibility:public"],
)

swift_library(
    name = "AvatarServiceClient",
    module_name = "AvatarServiceClient",
    srcs = glob([
        "Sources/AvatarServiceClient/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        ":AvatarServiceAPI",
    ],
    visibility = ["//visibility:public"],
)

swift_library(
    name = "AvatarIntegration",
    module_name = "AvatarIntegration",
    srcs = [
        "Sources/AvatarEngine.swift",
        "Sources/AvatarDesignSystem.swift",
        "Sources/AvatarFlowViewController.swift",
        "Sources/AvatarIntegrationEntryPoint.swift",
        "Sources/AvatarCreationIntroView.swift",
        "Sources/AvatarCreationIntroViewController.swift",
        "Sources/AvatarMetalView.swift",
        "Sources/AvatarModelResource.swift",
        "Sources/AvatarRendererViewController.swift",
        "Sources/AvatarResourceBundle.swift",
        "Sources/AvatarSelfieIntroView.swift",
        "Sources/AvatarSelfieIntroViewController.swift",
    ],
    copts = [
        "-warnings-as-errors",
    ],
    data = [
        ":AvatarIntegrationBundle",
    ],
    deps = [
        ":AvatarEngineBridge",
    ],
    visibility = ["//visibility:public"],
)
