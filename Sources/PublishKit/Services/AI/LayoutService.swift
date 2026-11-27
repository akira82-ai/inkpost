import Foundation

enum LayoutService {
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
        let pattern = protected + #"|(?<=[。！？；：.!?;:])(?:\\n){1,2}(?!\\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return body }
        var result = body
        for match in regex.matches(in: body, range: NSRange(body.startIndex..., in: body)).reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let marker = result[range]
            if marker == #"\n"# || marker == #"\n\n"# {
                result.replaceSubrange(range, with: marker.count == 2 ? "\n" : "\n\n")
            }
        }
        return result
    }

    static func validatedBody(from response: String, original: String) throws -> String {
        guard let body = try? JSONDecoder().decode(String.self, from: Data(response.utf8)) else {
            throw AIError.invalidResponse
        }
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
        guard String(before.text).utf8.elementsEqual(String(after.text).utf8),
              protectedText(original).elementsEqual(protectedText(body), by: { $0.utf8.elementsEqual($1.utf8) }),
              before.gaps.first == after.gaps.first, before.gaps.last == after.gaps.last else {
            throw AIError.invalidResponse
        }
        let punctuation = "。！？；：.!?;:"
        for offset in before.text.indices {
            let old = before.gaps[offset]
            let new = after.gaps[offset]
            if old == new { continue }
            guard new == "\n" || new == "\n\n",
                  old.allSatisfy({ $0 == " " || $0.isNewline }),
                  offset > 0, !old.isEmpty || punctuation.contains(before.text[offset - 1]) else {
                throw AIError.invalidResponse
            }
        }
        return body
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
