// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "DebugThings",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v15),
        .tvOS(.v15),
        .macOS(.v13),
        .watchOS(.v9),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "DebugThings", targets: ["DebugThings"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.12.0"),
    ],
    targets: [
        .target(
            name: "DebugThings",
            dependencies: [
                .product(name: "Logging", package: "swift-log")
            ],
            resources: [.copy("PrivacyInfo.xcprivacy")]
        ),
        .testTarget(
            name: "DebugThingsTests",
            dependencies: ["DebugThings"]
        ),
    ]
)
