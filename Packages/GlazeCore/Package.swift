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
        .library(name: "GlazeBooks", targets: ["GlazeBooks"]),
        .library(name: "GlazeTranscription", targets: ["GlazeTranscription"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.9.0"),
        // 7-Zip, for the archives comic downloads actually come in. Pure Swift and
        // MIT — which is why this is here and a RAR decoder is not (`docs/33`).
        .package(url: "https://github.com/tsolomko/SWCompression.git", from: "4.8.6")
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
        // Books and comics: zip, EPUB, and what counts as a volume. Split out for the
        // same reason as transcription — only iPhone and iPad have a bookshelf
        // (`docs/32`), and a television should not carry a reader it will never open.
        .target(
            name: "GlazeBooks",
            dependencies: [
                "GlazeCore",
                .product(name: "SWCompression", package: "SWCompression")
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
            dependencies: ["GlazeCore", "GlazeBooks"]
        )
    ]
)
