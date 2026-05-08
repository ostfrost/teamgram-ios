// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AvatarIntegration",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15)
    ],
    products: [
        .library(
            name: "AvatarIntegration",
            targets: ["AvatarIntegration"]
        ),
        .library(
            name: "AvatarServiceClient",
            targets: ["AvatarServiceClient"]
        ),
        .library(
            name: "AvatarAuthClient",
            targets: ["AvatarAuthClient"]
        )
    ],
    dependencies: [
        .package(name: "FilamentSPM", path: "Vendor/Filament")
    ],
    targets: [
        .target(
            name: "AvatarServiceAPI",
            path: "Sources/AvatarServiceAPI"
        ),
        .target(
            name: "AvatarAuthClient",
            dependencies: [
                "AvatarServiceAPI"
            ],
            path: "Sources/AvatarAuthClient"
        ),
        .target(
            name: "AvatarServiceClient",
            dependencies: [
                "AvatarServiceAPI"
            ],
            path: "Sources/AvatarServiceClient"
        ),
        .target(
            name: "AvatarEngineBridge",
            dependencies: [
                .product(
                    name: "Filament",
                    package: "FilamentSPM",
                    condition: .when(platforms: [.iOS])
                )
            ],
            path: ".",
            exclude: [
                "Package.swift",
                "Sources/AvatarEngine.swift",
                "Sources/AvatarMetalView.swift",
                "Sources/AvatarAuthClient",
                "Sources/AvatarServiceAPI",
                "Sources/AvatarServiceClient"
            ],
            sources: [
                "Sources/Bridge/AvatarEngineBridge.mm",
                "Sources/Bridge/AvatarNativeEngineAdapter.h",
                "Sources/Bridge/AvatarNativeEngineAdapter.mm"
            ],
            publicHeadersPath: "PublicHeaders",
            cxxSettings: [
                .headerSearchPath("PublicHeaders"),
                .headerSearchPath("Vendor/Filament/Artifacts/filament/include")
            ]
        ),
        .target(
            name: "AvatarIntegration",
            dependencies: [
                "AvatarEngineBridge"
            ],
            path: "Sources",
            exclude: [
                "Bridge",
                "AvatarRepositoryMetalView.swift",
                "AvatarAuthClient",
                "AvatarServiceAPI",
                "AvatarServiceClient",
                "RepositoryAvatarEngine.swift",
                "RepositoryAvatarRendererViewController.swift"
            ],
            sources: [
                "AvatarEngine.swift",
                "AvatarIntegrationEntryPoint.swift",
                "AvatarMetalView.swift",
                "AvatarModelResource.swift",
                "AvatarRendererViewController.swift",
                "AvatarSnapshotTesting.swift",
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "AvatarServiceClientTests",
            dependencies: [
                "AvatarAuthClient",
                "AvatarServiceClient"
            ],
            path: "Tests/AvatarServiceClientTests"
        )
    ],
    cxxLanguageStandard: .cxx17
)
