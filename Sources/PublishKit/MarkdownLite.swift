import Foundation

/// happy path 用的最小 Markdown → HTML（标题/段落/粗体/斜体/链接/图片/引用/列表）。
/// 复杂排版后续交给 AI 适配层，这里只保证"能看"。
public enum MarkdownLite {
    public static func render(_ markdown: String) -> String {
        var out: [String] = []
        var inList = false
        for rawLine in markdown.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                if inList { out.append("</ul>"); inList = false }
                continue
            }
            if line.hasPrefix("# ") {
                if inList { out.append("</ul>"); inList = false }
                out.append("<h1>\(inline(line.dropFirst(2)))</h1>")
            } else if line.hasPrefix("## ") {
                if inList { out.append("</ul>"); inList = false }
                out.append("<h2>\(inline(line.dropFirst(3)))</h2>")
            } else if line.hasPrefix("### ") {
                if inList { out.append("</ul>"); inList = false }
                out.append("<h3>\(inline(line.dropFirst(4)))</h3>")
            } else if line.hasPrefix("> ") {
                if inList { out.append("</ul>"); inList = false }
                out.append("<blockquote>\(inline(line.dropFirst(2)))</blockquote>")
            } else if line.hasPrefix("- ") {
                if !inList { out.append("<ul>"); inList = true }
                out.append("<li>\(inline(line.dropFirst(2)))</li>")
            } else {
                if inList { out.append("</ul>"); inList = false }
                out.append("<p>\(inline(line))</p>")
            }
        }
        if inList { out.append("</ul>") }
        return out.joined(separator: "\n")
    }

    /// 纯文本化（动态平台用：去标题符号/加粗/图片标记，保留链接文字）
    public static func plain(_ markdown: String) -> String {
        var out: [String] = []
        for rawLine in markdown.components(separatedBy: "\n") {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            while line.hasPrefix("#") { line.removeFirst() }
            line = line.trimmingCharacters(in: .whitespaces)
            // 链接 [t](u) → t；图片 ![alt](u) → [图片: alt]
            line = line.replacingOccurrences(
                of: #"!\[([^\]]*)\]\(([^)]+)\)"#,
                with: "[图片: $1]",
                options: .regularExpression)
            line = line.replacingOccurrences(
                of: #"\[([^\]]+)\]\(([^)]+)\)"#,
                with: "$1 ($2)",
                options: .regularExpression)
            line = line.replacingOccurrences(
                of: #"\*\*([^*]+)\*\*"#,
                with: "$1",
                options: .regularExpression)
            line = line.replacingOccurrences(
                of: #"\*([^*]+)\*"#,
                with: "$1",
                options: .regularExpression)
            out.append(line)
        }
        return out.joined(separator: "\n")
    }

    /// 行内：**粗体** *斜体* [文字](链接) ![alt](图片)
    /// 先转义原文，再插入可信标签，避免生成物被二次转义。
    static func inline(_ s: some StringProtocol) -> String {
        var t = String(s).escapingHTML()
        // 图片（先于链接处理）
        t = t.replacingOccurrences(
            of: #"!\[([^\]]*)\]\(([^)]+)\)"#,
            with: "<img src=\"$2\" alt=\"$1\">",
            options: .regularExpression
        )
        t = t.replacingOccurrences(
            of: #"\[([^\]]+)\]\(([^)]+)\)"#,
            with: "<a href=\"$2\">$1</a>",
            options: .regularExpression
        )
        t = t.replacingOccurrences(
            of: #"\*\*([^*]+)\*\*"#,
            with: "<b>$1</b>",
            options: .regularExpression
        )
        t = t.replacingOccurrences(
            of: #"\*([^*]+)\*"#,
            with: "<i>$1</i>",
            options: .regularExpression
        )
        return t
    }
}

extension String {
    func escapingHTML() -> String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
