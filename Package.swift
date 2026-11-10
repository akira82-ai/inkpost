// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PublishFlow",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        // 核心库：协议模型、本地存储、EgoLite 引擎
        .target(
            name: "PublishKit",
            exclude: ["Services/Channels/JuejinChannelAdapter.md", "Services/Channels/JikeChannelAdapter.md", "Services/Channels/ZhihuChannelAdapter.md", "Services/Channels/XChannelAdapter.md", "Services/Channels/WeiboChannelAdapter.md"],
            resources: [
                .copy("Adapters"),
                .copy("Fixtures"),
            ]
        ),
        // SwiftUI App
        .executableTarget(
            name: "PublishFlow",
            dependencies: ["PublishKit", .product(name: "Sparkle", package: "Sparkle")],
            resources: [.copy("Sparkle-LICENSE.txt")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
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
