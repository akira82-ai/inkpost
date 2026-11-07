// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PublishFlow",
    platforms: [.macOS(.v14)],
    targets: [
        // 核心库：协议模型、本地存储、EgoLite 引擎
        .target(
            name: "PublishKit",
            exclude: ["Services/Channels/JikeChannelAdapter.md", "Services/Channels/ZhihuChannelAdapter.md", "Services/Channels/XChannelAdapter.md"],
            resources: [
                .copy("Adapters"),
                .copy("Fixtures"),
            ]
        ),
        // SwiftUI App
        .executableTarget(
            name: "PublishFlow",
            dependencies: ["PublishKit"]
        ),
        // CLI 冒烟/演示工具
        .executableTarget(
            name: "flowctl",
            dependencies: ["PublishKit"]
        ),
        .testTarget(name: "PublishKitTests", dependencies: ["PublishKit"]),
        .testTarget(name: "PublishFlowTests", dependencies: ["PublishFlow"]),
    ]
)
