// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WaveCatchCore",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "WaveCatchCore", targets: ["WaveCatchCore"]),
    ],
    targets: [
        .target(name: "WaveCatchCore"),
        .testTarget(name: "WaveCatchCoreTests", dependencies: ["WaveCatchCore"]),
    ]
)
