// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NeptuneSDKiOS",
    platforms: [
        .iOS(.v17),
        .macOS(.v15)
    ],
    products: [
        .library(name: "NeptuneSDKiOS", targets: ["NeptuneSDKiOS"])
    ],
    targets: [
        .target(
            name: "NeptuneSDKiOS",
            path: "Sources/NeptuneSDKiOS"
        ),
        .testTarget(
            name: "NeptuneSDKiOSTests",
            dependencies: ["NeptuneSDKiOS"],
            path: "Tests/NeptuneSDKiOSTests"
        )
    ]
)
