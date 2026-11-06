import Foundation

final class JikeChannelAdapter: AgentChannelAdapter {
    override var platform: PlatformID { .jike }
    override var capabilities: ChannelCapabilities { .init(usesTitle: false, requiresLLM: true, maximumImages: 6, entryURL: "https://web.okjike.com") }
    override func goal(for request: ChannelRequest) -> String {
        let title = request.title, html = request.html, plain = request.body, tags = request.tags, assets = request.assets
        let tagText = tags.isEmpty ? "无" : tags.map { "#\($0)" }.joined(separator: " ")
        let imageInfo = assets.isEmpty ? "无图片" : "图片 \(assets.count) 张，本地路径：\(assets.joined(separator: "；"))"
        let opening = "把以下内容填入平台创作页，停在草稿状态（绝不点击发布/提交/发送类按钮）。\n- 标题：\(title)\n- 正文纯文本：\(plain)\n- 正文 HTML：\(html)\n- \(imageInfo)\n"

            return opening + """
                - 最终正文必须逐字填写（标题不并入正文）：\(expectedBody(for: request))
                - 平台：即刻（动态，纯文本）。入口：https://web.okjike.com
                - 在页面找到发布动态入口（带"发布/记录"字样的控件，点击后出现编辑弹窗），把正文填入弹窗编辑器，话题\(tagText == "无" ? "" : "（\(tagText)）")按平台习惯追加。
                - \(assets.isEmpty ? "无图片，跳过上传。" : "尝试把图片交给弹窗的上传控件；失败则返回 failed 并在 message 中说明。")
                - 完成后停在弹窗（不要关闭弹窗，关闭会丢失内容），绝对不要点击弹窗中的"发布"。
                - finish(status:"draftReady")。
                """
    }
}
