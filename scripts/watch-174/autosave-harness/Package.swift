// swift-tools-version: 6.4
import Foundation
import PackageDescription

let tca: Package.Dependency
if let checkout = ProcessInfo.processInfo.environment["LABCORD_TCA_CHECKOUT"], !checkout.isEmpty {
    tca = .package(path: checkout)
} else {
    tca = .package(
        url: "https://github.com/pointfreeco/swift-composable-architecture.git",
        exact: "1.26.2"
    )
}

let package = Package(
    name: "WatchRecordFocusedChecks",
    platforms: [.macOS(.v14)],
    dependencies: [tca],
    targets: [
        .target(name: "LabcordShared"),
        .target(name: "LabcordWatchOS", dependencies: [
            "LabcordShared",
            .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
        ]),
        .target(name: "WatchScreens", dependencies: [
            "LabcordShared", "LabcordWatchOS",
            .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
        ]),
        .testTarget(name: "WatchScreensTests", dependencies: ["WatchScreens", "LabcordShared"])
    ]
)
