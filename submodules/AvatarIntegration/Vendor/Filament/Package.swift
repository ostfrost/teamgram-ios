// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "FilamentSPM",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "Filament",
            targets: ["Filament"]
        )
    ],
    targets: [
        .target(
            name: "Filament",
            path: "Sources/Filament",
            sources: [
                "filament_spm_anchor.cc"
            ],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("../../Artifacts/filament/include")
            ],
            linkerSettings: [
                .linkedFramework("CoreGraphics", .when(platforms: [.iOS])),
                .linkedFramework("CoreVideo", .when(platforms: [.iOS])),
                .linkedFramework("Metal", .when(platforms: [.iOS])),
                .linkedFramework("OpenGLES", .when(platforms: [.iOS])),
                .linkedFramework("QuartzCore", .when(platforms: [.iOS])),
                .linkedFramework("UIKit", .when(platforms: [.iOS])),
                .linkedLibrary("c++", .when(platforms: [.iOS])),
                .unsafeFlags([
                    "-LArtifacts/filament/lib/universal",
                    "-lfilament",
                    "-lfilamat",
                    "-lgltfio_core",
                    "-lbackend",
                    "-lfilabridge",
                    "-lfilaflat",
                    "-lutils",
                    "-lgeometry",
                    "-lshaders",
                    "-libl-lite",
                    "-lbasis_transcoder",
                    "-lstb",
                    "-lktxreader",
                    "-ldracodec",
                    "-lzstd",
                    "-limage",
                    "-lbluegl",
                    "-lbluevk",
                    "-lsmol-v",
                    "-luberzlib",
                    "-luberarchive",
                    "-lmeshoptimizer"
                ], .when(platforms: [.iOS]))
            ]
        )
    ],
    cxxLanguageStandard: .cxx17
)
