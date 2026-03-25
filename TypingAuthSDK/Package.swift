// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TypingAuthSDK",
    platforms: [.iOS(.v16)],
    products: [
        .library(
            name: "TypingAuthSDK",
            targets: ["TypingAuthSDK"]
        ),
    ],
    targets: [
        .target(
            name: "TypingAuthSDK",
            path: "Sources/TypingAuthSDK",
            resources: [.copy("../../Resources/TypingAuthBase.mlmodel")]
        ),
    ]
)
