// swift-tools-version: 6.4
import PackageDescription

/// SwiftUI: the theme (palette, type, spacing, shapes, the serif's runtime registration), the reusable components
/// and the screens. Builds for the Mac too, so `swift build` checks it without a simulator.
let package = Package(
    name: "EnchiridionUI",
    platforms: [.iOS(.v27), .macOS(.v27)],
    products: [
        .library(name: "EnchiridionUI", targets: ["EnchiridionUI"]),
    ],
    dependencies: [
        .package(path: "../EnchiridionKit"),
        .package(path: "../EnchiridionCore"),
    ],
    targets: [
        .target(name: "EnchiridionUI", dependencies: [
            .product(name: "EnchiridionKit", package: "EnchiridionKit"),
            .product(name: "EnchiridionCore", package: "EnchiridionCore"),
        ]),
        // No test target: the logic worth testing lives in EnchiridionKit and EnchiridionCore. If one is added,
        // name it EnchiridionViewTests, never EnchiridionUITests, which reads as an XCUITest bundle.
    ]
)
