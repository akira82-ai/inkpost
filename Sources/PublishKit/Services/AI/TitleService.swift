import Foundation

enum TitleService {
    struct Draft: Encodable {
        let body: String
        let platform: String?
        let maxLength: Int?
    }

    static func generate(draft: Draft) async throws -> String {
        let url = try Resources.url("title", ext: "txt", sub: "Prompts")
        let prompt = try String(contentsOf: url, encoding: .utf8)
        let input = String(decoding: try JSONEncoder().encode(draft), as: UTF8.self)
        let response = try await AIClient.shared.complete(configuration: AISettings().load(),
            key: AISettings.readKey(), system: prompt, text: input)
        return try title(from: response, maxLength: draft.maxLength)
    }

    static func title(from response: String, maxLength: Int? = nil) throws -> String {
        guard let title = try? JSONDecoder().decode(String.self, from: Data(response.utf8)),
              title.count <= min(20, maxLength ?? 20),
              !title.contains(where: { $0.isNewline || $0 == "#" || $0 == "＃" }),
              title == title.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw AIError.invalidResponse
        }
        return title
    }
}
