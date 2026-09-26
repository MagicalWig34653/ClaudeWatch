// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeWatchCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ClaudeWatchCore", targets: ["ClaudeWatchCore"]),
    ],
    targets: [
        .target(name: "ClaudeWatchCore"),
        .testTarget(
            name: "ClaudeWatchCoreTests",
            dependencies: ["ClaudeWatchCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
