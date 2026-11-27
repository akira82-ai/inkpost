import Foundation

enum TopicService {
    struct Draft: Encodable, Equatable {
        let title: String
        let body: String
        let platform: String?
    }

    static func generate(draft: Draft) async throws -> [String] {
        let configuration = AISettings().load()
        let key = try AISettings.readKey()
        let promptURL = try Resources.url("topics", ext: "txt", sub: "Prompts")
        let prompt = try String(contentsOf: promptURL, encoding: .utf8)
        let input = String(decoding: try JSONEncoder().encode(draft), as: UTF8.self)
        let response = try await AIClient.shared.complete(configuration: configuration, key: key,
                                                         system: prompt, text: input)
        return try tags(from: response, excluding: draft.body, limit: draft.platform == "X" ? 2 : 5)
    }

    static func tags(from response: String, excluding body: String, limit: Int) throws -> [String] {
        guard let values = try? JSONDecoder().decode([String].self, from: Data(response.utf8)),
              values.allSatisfy({ (1...40).contains($0.count) && $0.allSatisfy { $0.isLetter || $0.isNumber } }) else {
            throw AIError.invalidResponse
        }
        let pattern = try NSRegularExpression(pattern: #"[#＃]([\p{L}\p{M}\p{N}_-]+)"#)
        let matches = pattern.matches(in: body, range: NSRange(body.startIndex..., in: body))
        var seen = Set(matches.compactMap { match in
            Range(match.range(at: 1), in: body).map { normalized(String(body[$0])) }
        })
        return Array(values.filter { seen.insert(normalized($0)).inserted }.prefix(limit))
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }
}
