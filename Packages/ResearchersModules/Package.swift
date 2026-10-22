// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ResearchersModules", // researchers-sdk-ios, researchers-package-swift
    platforms: [.iOS(.v26), .watchOS(.v26)],
    products: [
        // Products define the executables and libraries a package produces,
        // making them visible to other packages.
        .library(
            name: "Shared", // UniversalKit, UniversalFramework
            targets: ["Shared"]
        ) // ios& watchos 공통 | ios 전용 | watchos 전용 으로 라이브러리 분리가능~!
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "Shared", // 공통 모델 등등
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency")
            ],
        )
    ]
)
