import Foundation

// MARK: - 平台

/// 平台身份；实际可用性由渠道注册表决定。
public enum PlatformID: String, Codable, CaseIterable, Identifiable, Sendable {
    case simFixture = "sim-fixture" // 内置模拟平台（本地 fixture 页面）
    case zhihu
    case xiaohongshu
    case weibo
    case jike
    case juejin
    case bilibili
    case x

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .simFixture: return "模拟平台"
        case .zhihu: return "知乎"
        case .xiaohongshu: return "小红书"
        case .weibo: return "微博"
        case .jike: return "即刻"
        case .juejin: return "掘金沸点"
        case .bilibili: return "B站动态"
        case .x: return "X"
        }
    }

    /// Compatibility accessors backed by registered channel capabilities.
    public var isAvailable: Bool { ChannelRegistry.standard.adapter(for: self) != nil }
    public var isArticle: Bool { ChannelRegistry.standard.adapter(for: self)?.capabilities.isArticle == true }
    public var entryURL: String? { ChannelRegistry.standard.adapter(for: self)?.capabilities.entryURL }

}

// MARK: - 内容与任务协议（Swift ↔ 适配器脚本 共享的 JSON 契约）

public struct Article: Codable {
    public init(title: String, markdown: String, html: String) {
        self.title = title; self.markdown = markdown; self.html = html
    }
    public var title: String
    public var markdown: String
    public var html: String
}

public struct TaskAsset: Codable {
    public init(id: String, fileName: String, mimeType: String, path: String) {
        self.id = id; self.fileName = fileName; self.mimeType = mimeType; self.path = path
    }
    public var id: String
    public var fileName: String
    public var mimeType: String
    /// 绝对路径；适配器脚本经 setInputFiles 直接使用
    public var path: String
}

public struct TaskTarget: Codable {
    public init(platform: PlatformID, editorURL: String) {
        self.platform = platform; self.editorURL = editorURL
    }
    public var platform: PlatformID
    /// 目标编辑页地址（sim 为 file:// fixture；真实平台为创作页 URL）
    public var editorURL: String
}

/// CLI 模拟任务：编码后内嵌到脚本，交给本地模拟适配器读取。
public struct PublishTask: Codable {
    public init(postId: String, spaceName: String, article: Article, assets: [TaskAsset], target: TaskTarget) {
        self.postId = postId; self.spaceName = spaceName; self.article = article
        self.assets = assets; self.target = target
    }
    public var postId: String
    /// TaskSpace 名称，跨调用恢复同一组页面
    public var spaceName: String
    public var article: Article
    public var assets: [TaskAsset]
    public var target: TaskTarget
}

// MARK: - 状态机

public enum TargetPhase: String, Codable {
    case cancelled
    case needLogin      // 需要用户登录
    case pending        // 未开始
    case preparing      // 适配器填充中
    case awaitingConfirm // 草稿就绪，等待人工在浏览器确认发布
    case finalizing     // 收尾中（回读结果）
    case published      // 已发布（含回执）
    case failed         // 失败（含原因，可重试）
}

public struct TargetState: Codable {
    public init(platform: PlatformID) {
        self.platform = platform
    }
    public var platform: PlatformID
    public var phase: TargetPhase = .pending
    public var message: String?
    public var receiptURL: String?
    /// ego TaskSpace 数字 id（由适配器上报，finalize 时可用于 claim）
    public var spaceID: Int?
    public var updatedAt: Date = Date()

    public var canPrepare: Bool { phase == .pending || phase == .failed }
    public var canConfirm: Bool { phase == .awaitingConfirm }
}

// MARK: - 帖子

public struct Post: Codable, Identifiable {
    public init() {}
    public var id: String = UUID().uuidString
    public var title: String = ""
    public var markdown: String = ""
    /// 图片等素材的绝对路径
    public var assetPaths: [String] = []
    public var targetStates: [TargetState] = []
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public mutating func state(for platform: PlatformID) -> TargetState {
        if let i = targetStates.firstIndex(where: { $0.platform == platform }) {
            return targetStates[i]
        }
        let s = TargetState(platform: platform)
        targetStates.append(s)
        return s
    }

    public mutating func setState(_ s: TargetState) {
        if let i = targetStates.firstIndex(where: { $0.platform == s.platform }) {
            targetStates[i] = s
        } else {
            targetStates.append(s)
        }
        updatedAt = Date()
    }
}
