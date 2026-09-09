// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AnthropicUsageMenuBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "AnthropicUsageMenuBar",
            targets: ["AnthropicUsageMenuBar"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "AnthropicUsageMenuBar",
            dependencies: ["UsageCore"],
            path: "Sources/App"
        ),
        .target(name: "UsageCore", path: "Sources/Core"),
        .executableTarget(name: "UsageProbe", dependencies: ["UsageCore"], path: "Sources/Probe"),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"], path: "Tests")
    ]
)
