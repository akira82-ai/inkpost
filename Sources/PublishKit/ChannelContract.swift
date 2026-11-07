import Foundation

/// Stable in-process protocol. Codes are independent of presentation text.
public enum ChannelStage: String, Codable, Sendable {
    case validatingRequest, openingEditor, checkingLogin, fillingContent, uploadingAssets, verifyingContent
}
public enum ChannelErrorCode: String, Codable, Sendable {
    case contentUnsupported, loginRequired, editorUnavailable
    case uploadFailed, verificationFailed, operationResultUnknown, executionFailed, invalidCommand
}
public enum ChannelRecovery: String, Codable, Sendable {
    case retryAllowed, loginRequired, inspectionRequired, contentChangeRequired, notRecoverable
}
public struct ChannelFailure: Error, LocalizedError, Equatable, Sendable {
    public let code: ChannelErrorCode
    public let stage: ChannelStage
    public let detail: String
    public let recovery: ChannelRecovery
    public let diagnosticID: UUID
    public init(code: ChannelErrorCode, stage: ChannelStage, detail: String, recovery: ChannelRecovery, diagnosticID: UUID = UUID()) {
        self.code = code; self.stage = stage; self.detail = detail; self.recovery = recovery; self.diagnosticID = diagnosticID
    }
    public var errorDescription: String? { detail }
}
public enum ChannelOutcome: Equatable, Sendable {
    case readyForReview(message: String)
    case waitingForUser(ChannelFailure)
    case failed(ChannelFailure)

    public var failure: ChannelFailure? {
        switch self { case .waitingForUser(let failure), .failed(let failure): return failure; default: return nil }
    }
    public var canResume: Bool {
        guard let recovery = failure?.recovery else { return false }
        return [.retryAllowed, .loginRequired, .inspectionRequired].contains(recovery)
    }
}
public enum ChannelCommand: String, Sendable { case prepare, resumeAfterUser }
public struct ChannelExecutionID: Hashable, Sendable {
    public let taskID: UUID
    public let platform: PlatformID
    public let attemptID: UUID
    public init(taskID: UUID, platform: PlatformID, attemptID: UUID = UUID()) {
        self.taskID = taskID; self.platform = platform; self.attemptID = attemptID
    }
}
public enum ChannelEventPayload: Equatable, Sendable {
    case stage(ChannelStage)
    case progress(stage: ChannelStage, completed: Int, total: Int)
    case diagnostic(String)
}
public struct ChannelEvent: Sendable {
    public let execution: ChannelExecutionID
    public let payload: ChannelEventPayload
    public init(execution: ChannelExecutionID, payload: ChannelEventPayload) { self.execution = execution; self.payload = payload }
}

/// One invocation only. An adapter cannot emit events for another invocation.
@MainActor
public final class ChannelExecutionContext {
    public let execution: ChannelExecutionID
    public let command: ChannelCommand
    public let bridge: EgoBridge
    public private(set) var stage: ChannelStage = .validatingRequest
    private let onEvent: @MainActor @Sendable (ChannelEvent) -> Void
    private var active = true
    public init(execution: ChannelExecutionID, command: ChannelCommand, bridge: EgoBridge,
                onEvent: @escaping @MainActor @Sendable (ChannelEvent) -> Void) {
        self.execution = execution; self.command = command; self.bridge = bridge; self.onEvent = onEvent
    }
    public func advance(_ stage: ChannelStage) throws {
        try Task.checkCancellation()
        guard active else { return }
        self.stage = stage; onEvent(.init(execution: execution, payload: .stage(stage)))
    }
    public func progress(completed: Int, total: Int) throws {
        try Task.checkCancellation()
        guard active, total > 0, completed >= 0, completed <= total else { return }
        onEvent(.init(execution: execution, payload: .progress(stage: stage, completed: completed, total: total)))
    }
    public func diagnostic(_ message: String) {
        guard active, !Task.isCancelled else { return }
        onEvent(.init(execution: execution, payload: .diagnostic(message)))
    }
    func finish() { active = false }
    func mapFailure(_ error: Error) -> ChannelFailure {
        if let failure = error as? ChannelFailure { return failure }
        let writing = [.fillingContent, .uploadingAssets].contains(stage)
        return .init(code: writing ? .operationResultUnknown : (stage == .verifyingContent ? .verificationFailed : .executionFailed),
                     stage: stage, detail: error.localizedDescription,
                     recovery: writing || stage == .verifyingContent ? .inspectionRequired : .retryAllowed)
    }
}
