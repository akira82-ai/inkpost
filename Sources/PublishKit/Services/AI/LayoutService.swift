import Foundation

enum LayoutService {
    enum ResponseError: LocalizedError {
        case invalidJSON, changedContent, unsupportedSpacing

        var errorDescription: String? {
            switch self {
            case .invalidJSON: return "AI 返回的排版结果不是有效的 JSON 文本，原稿已保留。"
            case .changedContent: return "AI 修改了正文内容或受保护的链接、话题，原稿已保留。"
            case .unsupportedSpacing: return "AI 返回了不符合规则的换行或空格，原稿已保留。"
            }
        }
    }

    static func format(_ body: String) async throws -> String {
        let url = try Resources.url("layout", ext: "txt", sub: "Prompts")
        let prompt = try String(contentsOf: url, encoding: .utf8)
        let normalized = normalizeParagraphEscapes(body)
        let input = String(decoding: try JSONEncoder().encode(["body": normalized]), as: UTF8.self)
        let response = try await AIClient.shared.complete(configuration: AISettings().load(),
            key: AISettings.readKey(), system: prompt, text: input)
        return try validatedBody(from: response, original: normalized)
    }

    private static let structure = #"[`<>\[\]*_]|(?m)^(?:[ \t]|#{1,6}[ \t]|[+\-–][ \t]|~{3}|\d+[.)][ \t])|(?m) {2,}$"#
    private static let protected = #"(?:[a-zA-Z][a-zA-Z0-9+.-]*://|www\.)\S+|[#＃][\p{L}\p{M}\p{N}_-]+[#＃]?"#

    // Repair only prose paragraph markers. Leave code, links and tags intact.
    static func normalizeParagraphEscapes(_ body: String) -> String {
        guard body.range(of: structure, options: .regularExpression) == nil else { return body }
        let pattern = protected + #"|(?<=[。！？；：.!?;:]) *(?:\\n){1,2}(?!\\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return body }
        var result = body
        for match in regex.matches(in: body, range: NSRange(body.startIndex..., in: body)).reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let marker = result[range].drop(while: { $0 == " " })
            if marker == #"\n"# || marker == #"\n\n"# {
                result.replaceSubrange(range, with: marker.count == 2 ? "\n" : "\n\n")
            }
        }
        return result
    }

    static func validatedBody(from response: String, original: String) throws -> String {
        guard let decoded = try? JSONDecoder().decode(String.self, from: Data(response.utf8)) else {
            throw ResponseError.invalidJSON
        }
        let body = normalizeParagraphEscapes(decoded)
        if body.utf8.elementsEqual(original.utf8) { return original }

        // Structured drafts can contain significant whitespace, including Markdown hard breaks.
        if original.range(of: structure, options: .regularExpression) != nil { return original }

        let regex = try NSRegularExpression(pattern: protected)
        func protectedText(_ text: String) -> [String] {
            regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
                Range($0.range, in: text).map { String(text[$0]) }
            }
        }

        let before = parts(original)
        let after = parts(body)
        guard before.gaps.first == after.gaps.first, before.gaps.last == after.gaps.last else {
            throw ResponseError.unsupportedSpacing
        }
        if !String(before.text).utf8.elementsEqual(String(after.text).utf8) {
            guard try movableUnits(original) == movableUnits(body),
                  preservesQuotePairs(original: original, in: body) else { throw ResponseError.changedContent }
            return body
        }
        guard protectedText(original).elementsEqual(protectedText(body), by: { $0.utf8.elementsEqual($1.utf8) }) else {
            throw ResponseError.changedContent
        }
        let punctuation = "。！？；：.!?;:"
        for offset in before.text.indices {
            let old = before.gaps[offset]
            let new = after.gaps[offset]
            if old == new { continue }
            let sentenceBoundary = offset > 0 && punctuation.contains(before.text[offset - 1])
            let insertsBreak = (new == "\n" || new == "\n\n") && (!old.isEmpty || sentenceBoundary)
            let joinsAtPunctuation = offset > 0 && (sentenceBoundary || "，、".contains(before.text[offset - 1]))
            let joinsLines = old.contains(where: \.isNewline) && (new == " " || (new.isEmpty && joinsAtPunctuation))
            guard old.allSatisfy({ $0 == " " || $0.isNewline }), insertsBreak || joinsLines else {
                throw ResponseError.unsupportedSpacing
            }
        }
        return body
    }

    private static func preservesQuotePairs(original: String, in body: String) -> Bool {
        let lines = original.components(separatedBy: .newlines)
        for (quote, translation) in zip(lines, lines.dropFirst()) where translation.hasPrefix("（") {
            guard quote.first?.isASCII == true, quote.first?.isLetter == true else { continue }
            if body.range(of: quote + "\n" + translation, options: .literal) == nil { return false }
        }
        return true
    }

    // Compare exact bytes and occurrence counts, not a bag of words.
    private static func movableUnits(_ text: String) throws -> [Data: Int] {
        let boundaries = try NSRegularExpression(pattern: protected
            + #"|「[^」]*」|『[^』]*』|“[^”]*”|（[^）]*）|(?<boundary>[。！？]+|[.!?]+(?=\s|$)|\n[ \t]*\n)"#)
        var counts: [Data: Int] = [:]
        var start = text.startIndex
        func record(_ end: String.Index) {
            let unit = text[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
            if !unit.isEmpty { counts[Data(unit.utf8), default: 0] += 1 }
        }
        for match in boundaries.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range(withName: "boundary"), in: text) else { continue }
            record(range.upperBound)
            start = range.upperBound
        }
        record(text.endIndex)
        return counts
    }

    private static func parts(_ body: String) -> (text: [Character], gaps: [String]) {
        var text: [Character] = []
        var gaps = [""]
        for character in body {
            if character.isWhitespace {
                gaps[gaps.count - 1].append(character)
            } else {
                text.append(character)
                gaps.append("")
            }
        }
        return (text, gaps)
    }
}
