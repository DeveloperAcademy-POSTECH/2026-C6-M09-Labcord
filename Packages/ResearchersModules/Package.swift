// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "labcord-package-swift",
    platforms: [.iOS(.v27), .watchOS(.v26)],
    products: [
        .library(
            name: "LabcordKit",
            targets: ["LabcordShared", "LabcordDesignSystem"]
        ),
        .library(
            name: "LabcordiOS",
            targets: ["LabcordiOS"]
        ),
        .library(
            name: "LabcordWatchOS",
            targets: ["LabcordWatchOS"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/pointfreeco/swift-composable-architecture",
            from: "1.26.2"
        ),
        .package(
            url: "https://github.com/devicekit/DeviceKit",
            from: "5.9.0"
        ),
        .package(
            url: "https://github.com/hellosunghyun/swift-omni-parser",
            revision: "8403c2fc45dfa6ab946ef31bed1a509e6e35f412"
        )
    ],
    targets: [
        .target(
            name: "LabcordShared",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency")
            ],
        ),
        .target(
            name: "LabcordDesignSystem",
            dependencies: ["LabcordShared"],
            resources: [.process("Recources")]
        ),
        .target(
            name: "LabcordiOS",
            dependencies: [
                "LabcordShared",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(
                    name: "OmniParser",
                    package: "swift-omni-parser",
                    condition: .when(platforms: [.iOS])
                )
            ],
            resources: [.copy("Resources/ProtocolTermModel")],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .swiftLanguageMode(.v5)
            ]
        ),
        .target(
            name: "LabcordWatchOS",
            dependencies: [
                "LabcordShared",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "DeviceKit", package: "DeviceKit")
            ],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
