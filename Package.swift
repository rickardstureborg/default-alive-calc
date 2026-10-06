// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DefaultAliveCalculator",
    platforms: [.macOS(.v14)],
    targets: [
        // The tax checklist is compiled in (PackageResources.TaxPlaces_json) rather than
        // shipped as a resource bundle: the .app is assembled by hand in the Makefile, and a
        // SwiftPM resource bundle would need copying into it (and breaks codesign if it lands
        // in the bundle root). The browser mock fetches the same file.
        .target(name: "DefaultAliveCore", resources: [.embedInCode("TaxPlaces.json")]),
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
