// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DefaultAliveCalculator",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DefaultAliveCore"),
        .executableTarget(
            name: "DefaultAliveCalculator",
            dependencies: ["DefaultAliveCore"]
        ),
        .testTarget(
            name: "DefaultAliveCoreTests",
            dependencies: ["DefaultAliveCore"]
        ),
    ]
)
