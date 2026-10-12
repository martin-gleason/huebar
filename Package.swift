// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HueBar",
    platforms: [.macOS(.v14)],
    targets: [
        // Everything that talks to the bridge. No AppKit, so it can be tested headless.
        .target(name: "HueCore", path: "Sources/HueCore"),
        // The menu bar app. Thin: builds menus from HueCore snapshots and forwards clicks.
        .executableTarget(name: "HueBar", dependencies: ["HueCore"], path: "Sources/HueBar"),
        .testTarget(name: "HueCoreTests", dependencies: ["HueCore"], path: "Tests/HueCoreTests"),
    ]
)
