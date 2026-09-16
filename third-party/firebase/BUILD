load(
    "@build_bazel_rules_apple//apple:apple.bzl",
    "apple_static_xcframework_import",
)

sh_binary(
    name = "upload-symbols",
    srcs = ["upload-symbols.sh"],
    data = [
        "@bazel_tools//tools/bash/runfiles",
        "@firebase_crashlytics_binary//:upload-symbols",
    ],
    visibility = ["//visibility:public"],
)

apple_static_xcframework_import(
    name = "FBLPromises",
    xcframework_imports = ["@firebase_analytics_binary//:FBLPromises"],
)

apple_static_xcframework_import(
    name = "GoogleUtilities",
    xcframework_imports = ["@firebase_analytics_binary//:GoogleUtilities"],
)

apple_static_xcframework_import(
    name = "FirebaseCoreInternal",
    has_swift = True,
    xcframework_imports = ["@firebase_analytics_binary//:FirebaseCoreInternal"],
    deps = [":GoogleUtilities"],
)

apple_static_xcframework_import(
    name = "FirebaseCore",
    xcframework_imports = ["@firebase_analytics_binary//:FirebaseCore"],
    deps = [
        ":FirebaseCoreInternal",
        ":GoogleUtilities",
    ],
)

apple_static_xcframework_import(
    name = "FirebaseInstallations",
    sdk_frameworks = ["Security"],
    xcframework_imports = ["@firebase_analytics_binary//:FirebaseInstallations"],
    deps = [
        ":FBLPromises",
        ":FirebaseCore",
        ":GoogleUtilities",
    ],
)

apple_static_xcframework_import(
    name = "nanopb",
    xcframework_imports = ["@firebase_analytics_binary//:nanopb"],
)

apple_static_xcframework_import(
    name = "Promises",
    has_swift = True,
    xcframework_imports = ["@firebase_crashlytics_binary//:Promises"],
    deps = [":FBLPromises"],
)

apple_static_xcframework_import(
    name = "GoogleDataTransport",
    xcframework_imports = ["@firebase_crashlytics_binary//:GoogleDataTransport"],
    deps = [":nanopb"],
)

apple_static_xcframework_import(
    name = "FirebaseCoreExtension",
    xcframework_imports = ["@firebase_crashlytics_binary//:FirebaseCoreExtension"],
    deps = [":FirebaseCore"],
)

apple_static_xcframework_import(
    name = "FirebaseRemoteConfigInterop",
    has_swift = True,
    xcframework_imports = ["@firebase_crashlytics_binary//:FirebaseRemoteConfigInterop"],
)

apple_static_xcframework_import(
    name = "FirebaseSessions",
    has_swift = True,
    sdk_frameworks = [
        "Security",
        "SystemConfiguration",
    ],
    xcframework_imports = ["@firebase_crashlytics_binary//:FirebaseSessions"],
    deps = [
        ":FirebaseCore",
        ":FirebaseCoreExtension",
        ":FirebaseInstallations",
        ":GoogleDataTransport",
        ":GoogleUtilities",
        ":Promises",
        ":nanopb",
    ],
)

apple_static_xcframework_import(
    name = "FirebaseCrashlytics",
    alwayslink = True,
    has_swift = True,
    linkopts = ["-ObjC"],
    sdk_dylibs = [
        "c++",
        "z",
    ],
    sdk_frameworks = [
        "Security",
        "SystemConfiguration",
    ],
    xcframework_imports = ["@firebase_crashlytics_binary//:FirebaseCrashlytics"],
    deps = [
        ":FBLPromises",
        ":FirebaseCore",
        ":FirebaseCoreExtension",
        ":FirebaseInstallations",
        ":FirebaseRemoteConfigInterop",
        ":FirebaseSessions",
        ":GoogleDataTransport",
        ":GoogleUtilities",
        ":Promises",
        ":nanopb",
    ],
    visibility = ["//visibility:public"],
)

alias(
    name = "FirebaseCorePublic",
    actual = ":FirebaseCore",
    visibility = ["//visibility:public"],
)
