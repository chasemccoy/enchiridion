// swift-tools-version: 6.4
import PackageDescription

/// The app's models and decisions: `@MainActor @Observable` classes the views read, share input and compose logic,
/// slug planning. Foundation and Observation only, so `swift test` runs it on the Mac.
let package = Package(
    name: "EnchiridionCore",
    platforms: [.iOS(.v27), .macOS(.v27)],
    products: [
        .library(name: "EnchiridionCore", targets: ["EnchiridionCore"]),
    ],
    dependencies: [
        .package(path: "../EnchiridionKit"),
    ],
    targets: [
        .target(name: "EnchiridionCore", dependencies: [
            .product(name: "EnchiridionKit", package: "EnchiridionKit"),
        ]),
        .testTarget(name: "EnchiridionCoreTests", dependencies: [
            "EnchiridionCore",
            .product(name: "EnchiridionKit", package: "EnchiridionKit"),
        ]),
    ]
)
