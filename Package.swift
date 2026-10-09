// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScreenSwitch",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ScreenSwitch", targets: ["ScreenSwitch"]),
        .executable(name: "screenswitch-cli", targets: ["screenswitch-cli"]),
    ],
    targets: [
        .target(
            name: "PrivateDisplay",
            linkerSettings: [.linkedFramework("CoreGraphics")]
        ),
        .target(name: "ScreenSwitchCore", dependencies: ["PrivateDisplay"]),
        .executableTarget(name: "ScreenSwitch", dependencies: ["ScreenSwitchCore"]),
        .executableTarget(name: "screenswitch-cli", dependencies: ["ScreenSwitchCore"]),
        .testTarget(name: "ScreenSwitchCoreTests", dependencies: ["ScreenSwitchCore"]),
    ]
)
