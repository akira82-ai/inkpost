import Foundation
import Security

public struct AIConfiguration: Equatable, Sendable {
    public var endpoint: String
    public var model: String
    public init(endpoint: String = "https://api.openai.com/v1", model: String = "") {
        self.endpoint = endpoint; self.model = model
    }
    public func baseURL() throws -> URL {
        guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil,
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host)),
              !url.path.hasSuffix("/chat/completions"), !url.path.hasSuffix("/models") else {
            throw AIError.invalidEndpoint
        }
        return url
    }
}

public enum AIError: LocalizedError {
    case invalidEndpoint, missingModel, missingKey, keychain(OSStatus), http(Int), invalidResponse
    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "请填写 HTTPS 接口基础地址，本机服务可使用 HTTP。"
        case .missingModel: return "请填写或选择模型。"
        case .missingKey: return "请填写 API Key。"
        case .keychain(let status): return "无法访问钥匙串（\(status)）。"
        case .http(let status): return "AI 服务请求失败（HTTP \(status)）。"
        case .invalidResponse: return "AI 服务返回了无效或空白结果。"
        }
    }
}

public struct AISettings {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load() -> AIConfiguration {
        AIConfiguration(endpoint: defaults.string(forKey: "ai.endpoint") ?? "https://api.openai.com/v1",
                        model: defaults.string(forKey: "ai.model") ?? "")
    }
    public func save(_ configuration: AIConfiguration, key: String) throws {
        _ = try configuration.baseURL()
        guard !configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.missingModel }
        try Self.saveKey(key.trimmingCharacters(in: .whitespacesAndNewlines))
        defaults.set(configuration.endpoint.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "ai.endpoint")
        defaults.set(configuration.model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "ai.model")
    }
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.publishflow.ai", kSecAttrAccount as String: "apiKey"]
    }
    public static func readKey() throws -> String {
        var query = query
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else { throw AIError.keychain(status) }
        return key
    }
    private static func saveKey(_ key: String) throws {
        if key.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw AIError.keychain(status) }
            return
        }
        let data = Data(key.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw AIError.keychain(added) }
        } else if status != errSecSuccess { throw AIError.keychain(status) }
    }
}
