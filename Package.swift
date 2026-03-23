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
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", .upToNextMajor(from: "4.121.3"))
    ],
    targets: [
        .target(
            name: "NeptuneSDKiOS",
            dependencies: [
                .product(name: "Vapor", package: "vapor")
            ],
            path: "Sources/NeptuneSDKiOS"
        ),
        .testTarget(
            name: "NeptuneSDKiOSTests",
            dependencies: ["NeptuneSDKiOS"],
            path: "Tests/NeptuneSDKiOSTests"
        )
    ]
)
