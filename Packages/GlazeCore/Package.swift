// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "GlazeCore",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "GlazeCore", targets: ["GlazeCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.9.0")
    ],
    targets: [
        .target(
            name: "GlazeCore",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift")
            ],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
