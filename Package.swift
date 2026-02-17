// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ReadOut",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ReadOutCore",
            targets: ["ReadOutCore"]
        ),
        .library(
            name: "ReadOutIO",
            targets: ["ReadOutIO"]
        ),
        .library(
            name: "ReadOutPersistence",
            targets: ["ReadOutPersistence"]
        )
    ],
    targets: [
        .target(
            name: "ReadOutCore"
        ),
        .target(
            name: "ReadOutIO",
            dependencies: ["ReadOutCore"]
        ),
        .target(
            name: "ReadOutPersistence",
            dependencies: ["ReadOutCore"]
        ),
        .testTarget(
            name: "ReadOutCoreTests",
            dependencies: ["ReadOutCore"]
        ),
        .testTarget(
            name: "ReadOutIOTests",
            dependencies: ["ReadOutIO"]
        ),
    ]
)
