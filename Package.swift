// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AnalyticsBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AnalyticsBar", targets: ["AnalyticsBar"])
    ],
    targets: [
        .executableTarget(
            name: "AnalyticsBar",
            path: "Sources/AnalyticsBar",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "AnalyticsBarTests",
            dependencies: ["AnalyticsBar"],
            path: "Tests/AnalyticsBarTests"
        )
    ]
)
