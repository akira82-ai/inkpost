import Foundation

public struct DispatchSettings {
    public static let baseURL = "https://api.deepseek.com"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> LLMConfig {
        LLMConfig(baseURL: Self.baseURL,
            apiKey: defaults.string(forKey: "deepseek.apiKey") ?? "",
            model: defaults.string(forKey: "deepseek.model") ?? "deepseek-chat")
    }

    public func save(apiKey: String, model: String) {
        defaults.set(apiKey, forKey: "deepseek.apiKey")
        defaults.set(model, forKey: "deepseek.model")
    }
}
