import Foundation

final class FixtureChannelAdapter: AgentChannelAdapter {
    override var platform: PlatformID { .simFixture }
    override var capabilities: ChannelCapabilities { .init(usesTitle: true, requiresLLM: true, maximumImages: 6, isArticle: true) }
    override func goal(for request: ChannelRequest) -> String {
        let title = request.title, html = request.html, plain = request.body, assets = request.assets
        let imageInfo = assets.isEmpty ? "无图片" : "图片 \(assets.count) 张，本地路径：\(assets.joined(separator: "；"))"
        let opening = "把以下内容填入平台创作页，停在草稿状态（绝不点击发布/提交/发送类按钮）。\n- 标题：\(title)\n- 正文纯文本：\(plain)\n- 正文 HTML：\(html)\n- \(imageInfo)\n"

            let fixture = (try? Resources.url("fixture-page", ext: "html", sub: "Fixtures"))?.absoluteString ?? ""
            return opening + """
                - 平台：模拟平台（fixture，本地页面）。入口：\(fixture)
                - 话题内容：\(request.tagText)
                - 标题填 input#title，正文 paste_html 到 #editor，图片 upload 到 input#files，话题填入 input#tags。
                - finish(status:"draftReady")。
                """
    }
    override func expectedBody(for request: ChannelRequest) -> String { request.body }
    @MainActor
    override func verify(request: ChannelRequest, bridge: EgoBridge, result: EgoBridge.Finish) async throws {
        try await DraftVerifier.verify(bridge: bridge, result: result, request: request, expectedBody: request.body, usesTitle: true, tagsTarget: "#tags")
    }
}
