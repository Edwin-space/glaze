// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "GlazeCore",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17)
    ],
    products: [
        .library(name: "GlazeCore", targets: ["GlazeCore"]),
        .library(name: "GlazeTranscription", targets: ["GlazeTranscription"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.9.0")
    ],
    targets: [
        // Everything the three platforms share: subtitle models and parsing, the
        // translation pipeline, media resources, and UPnP. No WhisperKit, which is what
        // lets this build for tvOS at all.
        .target(
            name: "GlazeCore",
            resources: [
                .process("Resources")
            ]
        ),
        // Speech recognition, split out because WhisperKit does not support tvOS. The
        // Apple TV app never transcribes — it plays what a Mac prepared — so keeping
        // this separate is the honest boundary rather than a workaround.
        .target(
            name: "GlazeTranscription",
            dependencies: [
                "GlazeCore",
                .product(name: "WhisperKit", package: "argmax-oss-swift")
            ]
        ),
        .testTarget(
            name: "GlazeCoreTests",
            dependencies: ["GlazeCore"]
        )
    ]
)
