import Foundation
import PublishKit

/// Short product copy for system notifications; never display selectors, stack traces or raw tool errors.
struct CompletionNoticePresentation {
    let completion: DispatchCompletion
    private var pending: [PlatformID] { completion.platforms.filter { completion.phases[$0] != .awaitingConfirm } }
    private var completedCount: Int { completion.platforms.count - pending.count }
    var title: String {
        if completion.phase == .cancelled { return "填写已停止" }
        if pending.isEmpty { return "\(completedCount) 个渠道已填好" }
        if completedCount == 0 { return "\(pending.count) 个渠道需要处理" }
        return "\(completedCount) 个渠道已填好，\(pending.count) 个待处理"
    }
    var body: String {
        let reason: String
        if completion.phase == .cancelled { reason = "内容已保留，请检查浏览器页面。" }
        else if pending.isEmpty { reason = "请确认各渠道内容，并手动发布。" }
        else if pending.count > 1 { reason = pending.map(\.title).joined(separator: "、") + "需要处理，已填好的内容已保留。" }
        else if let platform = pending.first {
            let failure = completion.failures[platform]
            if failure?.recovery == .loginRequired { reason = platform.title + "需要登录。" }
            else if failure?.recovery == .contentChangeRequired { reason = platform.title + "的内容需要调整。" }
            else if failure?.stage == .uploadingAssets { reason = platform.title + "的图片未处理完成。" }
            else if failure?.stage == .verifyingContent { reason = platform.title + "的填写结果需要检查。" }
            else { reason = platform.title + "页面暂时无法操作。" }
        } else { reason = "请检查任务状态。" }
        return reason + (completion.workspaceID == nil ? "请返回墨驿查看。" : "点击打开本次 ego 工作区。")
    }
    @MainActor static func deliver(_ completion: DispatchCompletion) {
        let copy = Self(completion: completion)
        Task {
            await CompletionNotifier().deliver(copy.body, title: copy.title,
                taskID: completion.taskID, workspaceID: completion.workspaceID)
        }
    }
}
