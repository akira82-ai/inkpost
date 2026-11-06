import Foundation
import Observation

@MainActor
@Observable
public final class DispatchModel {
    public init() {}
    // 内容
    public var title = ""
    public var markdown = ""
    public var tagsText = ""
    public var assetPaths: [String] = []
    public var assetData: [String: Data] = [:]

    // 平台选择
    public var selectedPlatforms: [PlatformID] = [.zhihu, .jike, .x]
    public var platformPhase: [PlatformID: TargetPhase] = [:]

    // 配置（DeepSeek）
    public var apiKey = ""
    public var model = "deepseek-chat"

    // 运行状态
    public var overallPhase: TargetPhase = .pending
    public var eventLog: [String] = []
    public var manualReceipt = ""
    public var errorMessage: String?
    public var notice: String?
    public var currentPlatform: PlatformID?
    public var platformMessages: [PlatformID: String] = [:]
    public var taskPlatforms: [PlatformID] = []

}
