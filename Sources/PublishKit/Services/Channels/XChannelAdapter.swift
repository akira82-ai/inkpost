import Foundation

final class XChannelAdapter: AgentChannelAdapter {
    override var platform: PlatformID { .x }
    override var capabilities: ChannelCapabilities { .init(usesTitle: false, requiresLLM: true, maximumImages: 4, entryURL: "https://x.com/compose/post") }
    override func goal(for request: ChannelRequest) -> String {
        let title = request.title, html = request.html, plain = request.body, assets = request.assets
        let imageInfo = assets.isEmpty ? "无图片" : "图片 \(assets.count) 张，本地路径：\(assets.joined(separator: "；"))"
        let opening = "把以下内容填入平台创作页，停在草稿状态（绝不点击发布/提交/发送类按钮）。\n- 标题：\(title)\n- 正文纯文本：\(plain)\n- 正文 HTML：\(html)\n- \(imageInfo)\n"

            return opening + """
                - 平台：X（动态，纯文本，上限 280 字符；标题并入第一行，超长时不要擅自改写，返回 failed 并说明需要用户调整）。
                - 入口：https://x.com/compose/post；若浏览器已打开 X 且弹出撰写窗，直接复用。
                - 正文填入撰写窗的文本区（contenteditable）。\(assets.isEmpty ? "" : "图片最多 4 张：把文件交给撰写窗自带的文件输入控件（upload）。")
                - 完成后自检文本已填入。停在撰写窗，不要点击"Post/发布"。
                - finish(status:"draftReady")。
                """
    }
}
