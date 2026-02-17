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
        ),
        .executable(
            name: "ReadOutMacApp",
            targets: ["ReadOutMacApp"]
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
        .executableTarget(
            name: "ReadOutMacApp",
            dependencies: ["ReadOutCore", "ReadOutIO", "ReadOutPersistence"]
        ),
        .testTarget(
            name: "ReadOutCoreTests",
            dependencies: ["ReadOutCore"],
            resources: [
                .process("Fixtures")
            ]
        ),
        .testTarget(
            name: "ReadOutIOTests",
            dependencies: ["ReadOutIO"]
        ),
        .testTarget(
            name: "ReadOutPersistenceTests",
            dependencies: ["ReadOutPersistence"]
        ),
    ]
)
