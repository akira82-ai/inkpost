import Foundation
import Testing
import PublishKit
@testable import PublishFlow

struct CompletionNoticePresentationTests {
    private func copy(completed: Bool, stage: ChannelStage = .openingEditor,
                      recovery: ChannelRecovery = .retryAllowed, workspaceID: Int? = 17) -> CompletionNoticePresentation {
        CompletionNoticePresentation(completion: DispatchCompletion(taskID: UUID(), workspaceID: workspaceID,
            phase: .failed, platforms: completed ? [.zhihu, .weibo] : [.weibo],
            phases: completed ? [.zhihu: .awaitingConfirm, .weibo: .failed] : [.weibo: .failed],
            failures: [.weibo: .init(code: .executionFailed, stage: stage,
                detail: "page.click timed out after 3004ms: Selector button[title=发微博] has a zero-sized box",
                recovery: recovery)]))
    }
    @Test func toolErrorsDoNotAppearInBanner() {
        let view = copy(completed: false)
        #expect(view.title == "1 个渠道需要处理")
        #expect(view.body == "微博页面暂时无法操作。点击打开本次 ego 工作区。")
        #expect(!view.body.contains("Selector"))
        #expect(!view.body.contains("3004"))
    }
    @Test func partialCompletionHasSpecificShortReasonAndCorrectDestination() {
        let login = copy(completed: true, recovery: .loginRequired)
        #expect(login.title == "1 个渠道已填好，1 个待处理")
        #expect(login.body == "微博需要登录。点击打开本次 ego 工作区。")
        #expect(copy(completed: true, stage: .uploadingAssets).body.hasPrefix("微博的图片未处理完成。"))
        #expect(copy(completed: true, stage: .verifyingContent).body.hasPrefix("微博的填写结果需要检查。"))
        let withoutSpace = copy(completed: false, workspaceID: nil)
        #expect(withoutSpace.body.hasSuffix("请返回墨驿查看。"))
        #expect(!withoutSpace.body.contains("点击打开"))
    }
}
