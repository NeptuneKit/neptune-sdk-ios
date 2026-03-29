import ProjectDescription

let packages: [Package] = [
    .package(path: "../.."),
    .remote(
        url: "https://github.com/Lakr233/LookInside.git",
        requirement: .upToNextMajor(from: "2.1.1")
    )
]

let appTarget = Target(
    name: "SimulatorApp",
    platform: .iOS,
    product: .app,
    bundleId: "com.neptunekit.demo.ios",
    deploymentTarget: .iOS(targetVersion: "17.0", devices: [.iphone]),
    infoPlist: .extendingDefault(with: [
        "CFBundleShortVersionString": "1.0",
        "CFBundleVersion": "1",
        "UILaunchStoryboardName": "LaunchScreen"
    ]),
    sources: ["App/Sources/**"],
    resources: ["App/Resources/**"],
    dependencies: [
        .package(product: "NeptuneSDKiOS"),
        .package(product: "LookinServer")
    ],
    settings: .settings(
        base: [
            "OTHER_LDFLAGS": "$(inherited) -ObjC"
        ]
    )
)

let testsTarget = Target(
    name: "SimulatorAppTests",
    platform: .iOS,
    product: .unitTests,
    bundleId: "com.neptunekit.demo.ios.tests",
    infoPlist: .default,
    sources: ["App/Tests/**"],
    dependencies: [
        .target(name: "SimulatorApp")
    ]
)

let project = Project(
    name: "SimulatorApp",
    organizationName: "NeptuneKit",
    packages: packages,
    targets: [appTarget, testsTarget]
)
