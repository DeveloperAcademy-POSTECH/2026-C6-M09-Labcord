// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "labcord-package-swift",
    platforms: [.iOS(.v26), .watchOS(.v26)],
    products: [
        // Products define the executables and libraries a package produces,
        // making them visible to other packages.
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
        )
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
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
