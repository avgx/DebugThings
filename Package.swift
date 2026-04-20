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
        .library(name: "DebugThingsPulseProxy", targets: ["DebugThingsPulseProxy"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.12.0"),
        .package(url: "https://github.com/avgx/Pulse.git", revision: "3827f6996ad471c0cedd42e29eac9303fe42bd73")
    ],
    targets: [
        .target(
            name: "DebugThings",
            dependencies: [
                .product(name: "Logging", package: "swift-log")
            ]
        ),
        .target(
            name: "DebugThingsPulseProxy",
            dependencies: [
                "DebugThings",
                "Pulse"
            ]
        ),
        .testTarget(
            name: "DebugThingsTests",
            dependencies: ["DebugThings"]
        ),
        .testTarget(
            name: "DebugThingsPulseProxyTests",
            dependencies: ["DebugThingsPulseProxy"]
        ),
    ]
)
