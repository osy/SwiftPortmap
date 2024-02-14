// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftPortmap",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "SwiftPortmap",
            targets: ["SwiftPortmap"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
    ],
    targets: [
        .target(
            name: "SwiftPortmap"),
        .executableTarget(
            name: "portmap",
            dependencies: [
                "SwiftPortmap",
                .product(name: "ArgumentParser", package: "swift-argument-parser")],
            path: "Sources/CLI"),
        .testTarget(
            name: "SwiftPortmapTests",
            dependencies: ["SwiftPortmap"]),
    ]
)
