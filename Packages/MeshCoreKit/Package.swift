// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MeshCoreKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MeshCoreKit", targets: ["MeshCoreKit"]),
    ],
    dependencies: [
        // CryptoKit is Apple-only; swift-crypto provides the same API on Linux (CI).
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "MeshCoreKit",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux])),
            ],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(name: "MeshCoreKitTests", dependencies: ["MeshCoreKit"]),
    ]
)
