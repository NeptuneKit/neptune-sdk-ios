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
        .package(url: "https://github.com/swhitty/FlyingFox.git", .upToNextMajor(from: "0.26.0"))
    ],
    targets: [
        .target(
            name: "NeptuneSDKiOS",
            dependencies: [
                .product(name: "FlyingFox", package: "FlyingFox"),
                .product(name: "FlyingSocks", package: "FlyingFox")
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
