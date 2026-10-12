// swift-tools-version: 6.4
import PackageDescription

/// Wire types, the HTTP client and the pure helpers (slugs, DB timestamps, predicates). Foundation only, so it builds
/// for iOS and for the Mac, where `swift test` runs it.
let package = Package(
    name: "EnchiridionKit",
    platforms: [.iOS(.v27), .macOS(.v27)],
    products: [
        .library(name: "EnchiridionKit", targets: ["EnchiridionKit"]),
    ],
    targets: [
        .target(name: "EnchiridionKit"),
        .testTarget(name: "EnchiridionKitTests", dependencies: ["EnchiridionKit"]),
    ]
)
