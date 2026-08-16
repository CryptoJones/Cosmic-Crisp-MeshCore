// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MeshCoreKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MeshCoreKit", targets: ["MeshCoreKit"]),
    ],
    targets: [
        .target(
            name: "MeshCoreKit",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(name: "MeshCoreKitTests", dependencies: ["MeshCoreKit"]),
    ]
)
