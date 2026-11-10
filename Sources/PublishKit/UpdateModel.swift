import Foundation
import Observation

public enum UpdatePhase: Equatable {
    case idle, checking, available, downloading, extracting, ready, installing, latest, failed
}

@MainActor @Observable
public final class UpdateModel {
    public init() {}
    public var phase: UpdatePhase = .idle
    public var version = ""
    public var releaseNotes = ""
    public var message: String?
    public var receivedBytes: UInt64 = 0
    public var expectedBytes: UInt64 = 0
    public var extractionProgress = 0.0
    public var isPresented = false
    public var automaticallyChecks = true
    public var isConfigured = false
    public var informationOnly = false
    public var canCancel = false
    public var canCheck = false
    public var installSessionActive = false
    public var progress: Double? {
        guard expectedBytes > 0 else { return nil }
        return min(1, Double(receivedBytes) / Double(expectedBytes))
    }
    public var hasReminder: Bool { [.available, .downloading, .extracting, .ready, .installing].contains(phase) }
}

/// Updates must never terminate an active task or discard in-memory user content.
public enum UpdateSafety {
    @MainActor public static func blockingReason(_ task: DispatchModel) -> String? {
        if task.isHandingOff || task.isSettling { return "正在交还浏览器，请稍后更新。" }
        if task.overallPhase == .preparing { return "正在填写，请先完成或停止当前任务。" }
        if task.overallPhase == .needLogin { return "还有渠道等待登录，请先继续填写或跳过后交接。" }
        if task.hasEnded { return "请先前往浏览器处理本次结果，再更新墨驿。" }
        if !task.title.isEmpty || !task.markdown.isEmpty || !task.assetPaths.isEmpty {
            return "还有未处理的草稿，请先处理内容后再更新。"
        }
        return nil
    }
}
