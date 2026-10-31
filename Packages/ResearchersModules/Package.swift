// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "labcord-package-swift",
    platforms: [.iOS(.v26), .watchOS(.v26)],
    products: [
        .library(
            name: "LabcordKit",
            targets: ["LabcordShared", "LabcordDesignSystem"]
        ),
        .library(
            name: "LabcordDesignSystemCatalog",
            targets: ["LabcordDesignSystemCatalog"]
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
            name: "LabcordDesignSystemCatalog",
            dependencies: ["LabcordDesignSystem", "LabcordShared"],
            resources: [.process("Resources")]
        ),
        .target(
            name: "LabcordiOS",
            dependencies: [
                "LabcordShared",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
            ],
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
