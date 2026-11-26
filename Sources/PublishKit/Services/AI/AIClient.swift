import Foundation

/// Shared OpenAI-compatible transport. Credentials and response bodies are never logged.
public final class AIClient: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    public static let shared = AIClient()
    private let sessionConfiguration: URLSessionConfiguration
    public init(sessionConfiguration: URLSessionConfiguration = .ephemeral) {
        self.sessionConfiguration = sessionConfiguration
        super.init()
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask,
                           willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest,
                           completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
    public func models(configuration: AIConfiguration, key: String) async throws -> [String] {
        let data = try await send(configuration: configuration, key: key, path: "models")
        struct Response: Decodable {
            struct Item: Decodable { let id: String }
            let data: [Item]
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { throw AIError.invalidResponse }
        let models = Array(Set(response.data.map(\.id).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })).sorted()
        guard !models.isEmpty else { throw AIError.invalidResponse }
        return models
    }
    public func complete(configuration: AIConfiguration, key: String, system: String, text: String) async throws -> String {
        guard !configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.missingModel }
        let payload: [String: Any] = ["model": configuration.model, "stream": false,
            "messages": [["role": "system", "content": system], ["role": "user", "content": text]]]
        let data = try await send(configuration: configuration, key: key, path: "chat/completions",
                                  body: JSONSerialization.data(withJSONObject: payload))
        struct Response: Decodable {
            struct Choice: Decodable { struct Message: Decodable { let content: String? }; let message: Message }
            let choices: [Choice]
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let content = response.choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.invalidResponse }
        return content
    }
    private func send(configuration: AIConfiguration, key: String, path: String, body: Data? = nil) async throws -> Data {
        let url = try configuration.baseURL().appendingPathComponent(path)
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty || url.scheme == "http" else { throw AIError.missingKey }
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let session = URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw AIError.http(http.statusCode) }
        guard data.count <= 4_000_000 else { throw AIError.invalidResponse }
        return data
    }
}
