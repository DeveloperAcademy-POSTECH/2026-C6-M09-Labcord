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
        )
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "LabcordShared",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency")
            ],
        ),
        .target(
            name: "LabcordDesignSystem",
            resources: [.process("Recources")]
        )
    ]
)
