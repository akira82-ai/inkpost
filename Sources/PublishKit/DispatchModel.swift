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
    public var selectedPlatforms: [PlatformID] = [.zhihu, .x]
    public var platformPhase: [PlatformID: TargetPhase] = [:]


    // 运行状态
    public var overallPhase: TargetPhase = .pending
    public var eventLog: [String] = []
    public var errorMessage: String?
    public var notice: String?
    public var currentPlatform: PlatformID?
    public var platformOutcomes: [PlatformID: ChannelOutcome] = [:]
    public var platformEvents: [PlatformID: ChannelEvent] = [:]
    public var platformMessages: [PlatformID: String] = [:]
    public var taskPlatforms: [PlatformID] = []
    public var isHandingOff = false
    public var history: [DispatchRecord] = []

}

public struct DispatchRecord: Identifiable {
    public let id = UUID()
    public let createdAt = Date()
    public let title: String
    public let markdown: String
    public let tags: String
    public let platforms: [PlatformID]
    public let assetPaths: [String]
    public let assetData: [String: Data]
    public let workspaceID: Int?
}
