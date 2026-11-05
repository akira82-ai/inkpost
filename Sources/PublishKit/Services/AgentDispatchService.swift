import Foundation

@MainActor
public protocol DispatchServicing {
    func prepare(platform: PlatformID, goal: String, config: LLMConfig,
                 onEvent: @escaping @Sendable (String) -> Void) async throws -> EgoBridge.Finish
    func readReceipt(for platform: PlatformID) async throws -> String
}

@MainActor
public final class AgentDispatchService: DispatchServicing {
    private var bridges: [PlatformID: EgoBridge] = [:]
    public init() {}

    public func prepare(platform: PlatformID, goal: String, config: LLMConfig,
                        onEvent: @escaping @Sendable (String) -> Void) async throws -> EgoBridge.Finish {
        let bridge = try EgoBridge(spaceName: "publish post \(platform.rawValue)-\(UUID().uuidString.prefix(6))",
                                   engine: EgoLiteEngine())
        bridges[platform] = bridge
        onEvent("调用 \(config.model) @ \(config.baseURL)")
        return try await Self.run(llm: OpenAICompatClient(config: config), bridge: bridge,
                                  goal: goal, onEvent: onEvent)
    }

    /// GUI 与 CLI 共用的 Agent 执行入口，支持脚本化模型验证。
    public static func run(llm: any LLMSession, bridge: EgoBridge, goal: String,
                           onEvent: @escaping @Sendable (String) -> Void) async throws -> EgoBridge.Finish {
        let loop = AgentLoop(llm: llm, bridge: bridge, maxSteps: 20)
        loop.onEvent = onEvent
        return try await loop.run(goal: goal)
    }

    public func readReceipt(for platform: PlatformID) async throws -> String {
        guard let bridge = bridges[platform] else {
            throw EgoBridge.BridgeError.toolFailed("没有可读取的草稿会话")
        }
        let raw = try await bridge.evaluate(
            js: "document.querySelector('#receipt') && document.querySelector('#receipt').dataset.url || ''")
        guard let data = raw.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EgoBridge.BridgeError.toolFailed("回执格式无效")
        }
        return object["value"] as? String ?? ""
    }
}
