// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Glaze",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Glaze", targets: ["Glaze"])
    ],
    targets: [
        .executableTarget(
            name: "Glaze",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
