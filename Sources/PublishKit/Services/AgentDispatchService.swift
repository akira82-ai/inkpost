import Foundation

@MainActor
public protocol DispatchServicing {
    func prepare(platform: PlatformID, goal: String, config: LLMConfig,
                 onEvent: @escaping @Sendable (String) -> Void) async throws -> EgoBridge.Finish
    func verifyDraft(platform: PlatformID, result: EgoBridge.Finish, title: String, body: String, imageCount: Int) async throws
    func beginTask() async throws
    func handOff() async throws
    func resumeControl() async throws
    func readReceipt(for platform: PlatformID) async throws -> String
}

public extension DispatchServicing {
    func verifyDraft(platform: PlatformID, result: EgoBridge.Finish, title: String, body: String, imageCount: Int) async throws {}
    func beginTask() async throws {}
    func handOff() async throws { throw EgoBridge.BridgeError.toolFailed("当前服务无法打开工作区") }
    func resumeControl() async throws {}
}

@MainActor
public final class AgentDispatchService: DispatchServicing {
    private var bridges: [PlatformID: EgoBridge] = [:]
    private var spaceName = ""
    private var spaceID: Int?
    private var handedOff = false
    public init() {}
    public func beginTask() async throws {
        spaceName = "inkpost \(UUID().uuidString)"
        bridges = [:]; spaceID = nil; handedOff = false
    }
    public func handOff() async throws {
        guard let id = spaceID else { throw EgoBridge.BridgeError.toolFailed("还没有可打开的浏览器工作区") }
        if handedOff { return }
        _ = try await EgoLiteEngine().runRaw(script: "const task = await taskSpace(\(id)); await task.handOff(); cliLog(JSON.stringify({ok:true}));")
        handedOff = true
    }
    public func resumeControl() async throws {
        guard handedOff, let id = spaceID else { return }
        _ = try await EgoLiteEngine().runRaw(script: "const task = await takeOverTaskSpace(\(id)); cliLog(JSON.stringify({ok:true}));")
        handedOff = false
    }

    public func prepare(platform: PlatformID, goal: String, config: LLMConfig,
                        onEvent: @escaping @Sendable (String) -> Void) async throws -> EgoBridge.Finish {
        if spaceName.isEmpty { try await beginTask() }
        let bridge: EgoBridge
        if let existing = bridges[platform] { bridge = existing }
        else {
            let engine = try EgoLiteEngine()
            let name = String(data: try JSONSerialization.data(withJSONObject: [spaceName]), encoding: .utf8)!
            let result = try await engine.runRaw(script: "const task = await taskSpace(\(name)[0]); const page = \(bridges.isEmpty ? "task.page(\"p1\")" : "await task.newPage()"); cliLog(JSON.stringify({label:page.label,spaceID:task.spaceId}));")
            guard let label = result.string("label") else { throw EgoBridge.BridgeError.noResult(result.rawOutput) }
            spaceID = result.json?["spaceID"] as? Int
            bridge = try EgoBridge(spaceName: spaceName, engine: engine, pageLabel: label)
            bridges[platform] = bridge
        }
        onEvent("调用 \(config.model) @ \(config.baseURL)")
        return try await Self.run(llm: OpenAICompatClient(config: config), bridge: bridge,
                                  goal: "\(goal)\n\n恢复要求：先检查现有页面与内容，已填写的标题、正文和图片不要重复插入；需要时修改原字段。", onEvent: onEvent)
    }

    /// GUI 与 CLI 共用的 Agent 执行入口，支持脚本化模型验证。
    public static func run(llm: any LLMSession, bridge: EgoBridge, goal: String,
                           onEvent: @escaping @Sendable (String) -> Void) async throws -> EgoBridge.Finish {
        let loop = AgentLoop(llm: llm, bridge: bridge, maxSteps: 20)
        loop.onEvent = onEvent
        return try await loop.run(goal: goal)
    }

    public func verifyDraft(platform: PlatformID, result: EgoBridge.Finish, title: String, body: String, imageCount: Int) async throws {
        guard let bridge = bridges[platform], let target = result.bodyTarget else { throw EgoBridge.BridgeError.toolFailed("未提供可验证的正文位置，请手工检查") }
        func read(_ selector: String) async throws -> [String: Any] {
            let raw = try await bridge.inspect(target: selector)
            guard let object = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any], let value = object["value"] as? [String: Any] else { throw EgoBridge.BridgeError.toolFailed("无法校验页面内容") }
            return value
        }
        func normalized(_ text: String) -> String { text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined() }
        let content = try await read(target)
        guard normalized(content["text"] as? String ?? "").contains(normalized(body)) else { throw EgoBridge.BridgeError.toolFailed("正文与提交内容不一致，请手工检查") }
        if platform.isArticle {
            guard let selector = result.titleTarget else { throw EgoBridge.BridgeError.toolFailed("缺少标题校验位置") }
            let value = try await read(selector)
            guard normalized(value["text"] as? String ?? "") == normalized(title) else { throw EgoBridge.BridgeError.toolFailed("标题未完整填写") }
        }
        if imageCount > 0 {
            guard let selector = result.imageTarget else { throw EgoBridge.BridgeError.toolFailed("缺少图片校验位置，请手工检查") }
            let value = try await read(selector)
            guard max(value["files"] as? Int ?? 0, value["images"] as? Int ?? 0) == imageCount else { throw EgoBridge.BridgeError.toolFailed("图片数量与提交内容不一致") }
        }
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
