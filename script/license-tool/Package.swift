// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "license-tool",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "license-tool"),
        .testTarget(name: "license-tool-tests", dependencies: ["license-tool"]),
    ]
)
