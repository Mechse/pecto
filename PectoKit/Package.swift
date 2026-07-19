// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PectoKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PectoKit", targets: ["PectoKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0")
    ],
    targets: [
        .target(name: "PectoKit", dependencies: ["Yams"]),
        .testTarget(name: "PectoKitTests", dependencies: ["PectoKit"]),
    ]
)
