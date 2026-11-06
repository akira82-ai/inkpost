import Foundation

public enum PlatformRules {
    /// 平台作战地图：入口 + 内容形态 + 平台特有认知（契约由系统提示词统一约束）
    public static func goal(for p: PlatformID, title: String, html: String, plain: String, tags: [String], assets: [String]) -> String {
        let tagText = tags.isEmpty ? "无" : tags.map { "#\($0)" }.joined(separator: " ")
        let imageInfo = assets.isEmpty ? "无图片" : "图片 \(assets.count) 张，本地路径：\(assets.joined(separator: "；"))"
        let opening = "把以下内容填入平台创作页，停在草稿状态（绝不点击发布/提交/发送类按钮）。\n- 标题：\(title)\n- 正文纯文本：\(plain)\n- 正文 HTML：\(html)\n- \(imageInfo)\n"

        switch p {
        case .zhihu:
            return opening + """
                - 平台：知乎专栏（文章）。入口：https://zhuanlan.zhihu.com/write
                - 标题填入顶部标题输入框；正文用 paste_html 注入富文本编辑器，并把话题\(tagText == "无" ? "" : "（\(tagText)）")追加到正文结尾。
                - 完成后自检：标题框 value 与正文长度都符合预期。知乎会自动存草稿，不要碰右下角的发布按钮。
                - finish(status:"draftReady")。
                """
        case .x:
            return opening + """
                - 平台：X（动态，纯文本，上限 280 字符；标题并入第一行，超长时不要擅自改写，返回 failed 并说明需要用户调整）。
                - 入口：https://x.com/compose/post；若浏览器已打开 X 且弹出撰写窗，直接复用。
                - 正文填入撰写窗的文本区（contenteditable）。\(assets.isEmpty ? "" : "图片最多 4 张：把文件交给撰写窗自带的文件输入控件（upload）。")
                - 完成后自检文本已填入。停在撰写窗，不要点击"Post/发布"。
                - finish(status:"draftReady")。
                """
        case .jike:
            return opening + """
                - 平台：即刻（动态，纯文本）。入口：https://web.okjike.com
                - 在页面找到发布动态入口（带"发布/记录"字样的控件，点击后出现编辑弹窗），把正文填入弹窗编辑器，话题\(tagText == "无" ? "" : "（\(tagText)）")按平台习惯追加。
                - \(assets.isEmpty ? "无图片，跳过上传。" : "尝试把图片交给弹窗的上传控件；失败则返回 failed 并在 message 中说明。")
                - 完成后停在弹窗（不要关闭弹窗，关闭会丢失内容），绝对不要点击弹窗中的"发布"。
                - finish(status:"draftReady")。
                """
        case .simFixture:
            let fixture = (try? Resources.url("fixture-page", ext: "html", sub: "Fixtures"))?.absoluteString ?? ""
            return opening + """
                - 平台：模拟平台（fixture，本地页面）。入口：\(fixture)
                - 标题填 input#title，正文 paste_html 到 #editor，图片 upload 到 input#files，话题填入 input#tags。
                - finish(status:"draftReady")。
                """
        default:
            return opening
        }
    }

}
