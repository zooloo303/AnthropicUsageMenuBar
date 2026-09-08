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
            path: "Sources"
        )
    ]
)
