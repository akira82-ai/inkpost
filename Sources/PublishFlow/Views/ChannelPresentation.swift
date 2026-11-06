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
        case .validatingRequest: return "检查内容与配置"
        case .openingEditor: return "打开编辑器"
        case .checkingLogin: return "检查登录状态"
        case .fillingContent: return "填写正文与标签"
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
