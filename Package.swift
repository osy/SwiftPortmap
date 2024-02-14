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
    targets: [
        .target(
            name: "SwiftPortmap"),
        .testTarget(
            name: "SwiftPortmapTests",
            dependencies: ["SwiftPortmap"]),
    ]
)
