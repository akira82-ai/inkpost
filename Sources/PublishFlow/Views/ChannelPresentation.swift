import PublishKit

extension ChannelRecovery {
    var actionTitle: String {
        switch self {
        case .retryAllowed: return "重试此渠道"
        case .loginRequired: return "我已登录，继续"
        case .inspectionRequired: return "我已检查页面，继续"
        case .contentChangeRequired: return "修改内容后重新开始"
        case .notRecoverable: return "无法继续"
        }
    }
}
extension ChannelStage {
    var presentationText: String {
        switch self {
        case .validatingRequest: return "检查内容"
        case .openingEditor: return "打开编辑器"
        case .checkingLogin: return "检查登录状态"
        case .fillingContent: return "填写正文"
        case .uploadingAssets: return "上传图片"
        case .verifyingContent: return "校验填写结果"
        }
    }
}
extension ChannelEventPayload {
    var presentationText: String {
        switch self {
        case .stage(let stage): return stage.presentationText
        case .progress(let stage, let completed, let total): return "\(stage.presentationText) · \(completed)/\(total)"
        case .diagnostic: return "正在执行渠道步骤"
        }
    }
}

/// Presentation only: task phases keep their domain meaning in PublishKit.
enum ChannelStatusPresentation: CaseIterable {
    case filling, ready, login, problem

    init(phase: TargetPhase) {
        switch phase {
        case .pending, .preparing, .finalizing: self = .filling
        case .awaitingConfirm, .published: self = .ready
        case .needLogin: self = .login
        case .failed, .cancelled: self = .problem
        }
    }
    var title: String {
        switch self {
        case .filling: return "填写中"
        case .ready: return "填写成功"
        case .login: return "需登录"
        case .problem: return "其他问题"
        }
    }
    var symbol: String {
        switch self {
        case .filling: return "arrow.triangle.2.circlepath"
        case .ready: return "checkmark"
        case .login: return "rectangle.portrait.and.arrow.right"
        case .problem: return "exclamationmark.diamond"
        }
    }
    var canOpen: Bool { self == .login || self == .problem }
}
