import Foundation

// MARK: - OpenAI 兼容 HTTP 客户端（零依赖，URLSession 直调）

public struct OpenAICompatClient: LLMSession {
    let config: LLMConfig

    public init(config: LLMConfig) { self.config = config }

    public func complete(messages: [ChatMessage], tools: [ToolDef]) async throws -> AssistantTurn {
        var body: [String: Any] = [
            "model": config.model,
            "messages": messages.map { m -> [String: Any] in
                var o: [String: Any] = ["role": m.role]
                if let c = m.content { o["content"] = c }
                if let t = m.tool_calls {
                    o["tool_calls"] = t.map { tc -> [String: Any] in
                        ["id": tc.id, "type": "function",
                         "function": ["name": tc.function.name, "arguments": tc.function.arguments]]
                    }
                }
                if let id = m.tool_call_id { o["tool_call_id"] = id }
                return o
            },
            "tools": tools.map { t -> [String: Any] in
                ["type": "function",
                 "function": ["name": t.function.name,
                              "description": t.function.description,
                              "parameters": t.function.parameters]]
            },
        ]

        var req = URLRequest(url: URL(string: config.baseURL + "/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 120

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AgentError.network("非 HTTP 响应") }
        guard http.statusCode == 200 else {
            let snippet = String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw AgentError.network("HTTP \(http.statusCode)：\(snippet)")
        }

        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let choices = obj["choices"] as? [[String: Any]], let first = choices.first,
              let message = first["message"] as? [String: Any] else {
            throw AgentError.network("响应缺少 choices.message")
        }
        let content = message["content"] as? String
        if let tcs = message["tool_calls"] as? [[String: Any]] {
            let calls = tcs.compactMap { tc -> ToolCall? in
                guard let fn = tc["function"] as? [String: Any],
                      let name = fn["name"] as? String,
                      let args = fn["arguments"] as? String else { return nil }
                return ToolCall(id: (tc["id"] as? String) ?? UUID().uuidString,
                                function: .init(name: name, arguments: args))
            }
            if !calls.isEmpty { return .toolCalls(calls) }
        }
        return .text(content ?? "")
    }

    public enum AgentError: LocalizedError {
        case network(String)
        public var errorDescription: String? {
            switch self {
            case .network(let m): return "LLM 调用失败：\(m)"
            }
        }
    }
}

// MARK: - 测试替身：脚本化假模型（验证管道，不打真实 API）

public final class ScriptedLLM: LLMSession {
    var queue: [AssistantTurn]
    public private(set) var receivedMessages: [ChatMessage] = []

    public init(_ turns: [AssistantTurn]) { queue = turns }

    public func complete(messages: [ChatMessage], tools: [ToolDef]) async throws -> AssistantTurn {
        receivedMessages = messages
        guard !queue.isEmpty else { return .text("脚本已耗尽") }
        return queue.removeFirst()
    }
}

// MARK: - 极简 Agent 循环

public final class AgentLoop {
    let llm: LLMSession
    let bridge: EgoBridge
    let maxSteps: Int
    public var onEvent: (@Sendable (String) -> Void)?

    public init(llm: LLMSession, bridge: EgoBridge, maxSteps: Int = 24) {
        self.llm = llm
        self.bridge = bridge
        self.maxSteps = maxSteps
    }

    /// 系统提示词：分发契约（安全边界在这里被声明）+ 工具认知
    public static let systemPrompt = """
    你是 PublishFlow 的内容分发 agent。目标：把给定的标题、正文、图片填入目标平台的创作/发布页面，最终停在可编辑草稿状态。

    铁律（违反即任务失败）：
    1. 绝不点击"发布 / 提交 / 确认发布 / 发送"类按钮——最终发布由人工确认。
    2. 不修改账号设置，不删除平台已有内容，不接受任何付费/授权弹窗。
    3. 页面是登录页/要求扫码 → 立即 finish(status:"needLogin")。
    4. 填充完成并自检通过（标题、正文、图片都到位）→ finish(status:"draftReady", draft_url:<当前页面URL>)。
    5. 页面结构与预期严重不符且两次尝试无法定位 → finish(status:"failed", message:<原因>)。

    工具与页面认知：
    - 先 navigate 打开页面，再 snapshot 获取语义树。快照节点形如 [ref=N]，fill/click 的 target 直接写 "@N"，也可用 CSS 选择器。
    - 标题类输入框用 fill；富文本正文（contenteditable）用 paste_html；图片上传控件（input[type=file]）用 upload。
    - 关键步骤后用 evaluate 回读校验（例如标题框的 value、编辑器的 textContent 长度）。
    - 行动要少而准：一般 6~10 步完成；不确定时先 snapshot 再行动。
    """

    /// 面向模型的工具 schema（执行映射到 EgoBridge）
    public static let toolDefs: [ToolDef] = [
        ToolDef(name: "navigate", description: "打开/复用页面并等待加载", parameters: [
            "type": "object", "required": ["url"],
            "properties": ["url": ["type": "string", "description": "页面 URL"]],
        ]),
        ToolDef(name: "snapshot", description: "读取页面语义快照（[ref=N] 树），用于定位元素", parameters: [
            "type": "object", "properties": [:],
        ]),
        ToolDef(name: "fill", description: "向输入框/文本域填充纯文本", parameters: [
            "type": "object", "required": ["target", "text"],
            "properties": [
                "target": ["type": "string", "description": "@ref 或 CSS 选择器"],
                "text": ["type": "string"],
            ],
        ]),
        ToolDef(name: "paste_html", description: "向富文本编辑器（contenteditable）注入 HTML", parameters: [
            "type": "object", "required": ["target", "html"],
            "properties": [
                "target": ["type": "string"],
                "html": ["type": "string", "description": "HTML 片段"],
            ],
        ]),
        ToolDef(name: "upload", description: "向文件上传控件提交本地文件", parameters: [
            "type": "object", "required": ["target", "paths"],
            "properties": [
                "target": ["type": "string", "description": "input[type=file] 的选择器或 @ref"],
                "paths": ["type": "array", "items": ["type": "string"], "description": "本地绝对路径"],
            ],
        ]),
        ToolDef(name: "evaluate", description: "在页面上下文执行只读 JS 并返回结果（用于校验）", parameters: [
            "type": "object", "required": ["js"],
            "properties": ["js": ["type": "string"]],
        ]),
        ToolDef(name: "finish", description: "结束任务并报告结果（这是你唯一正确的结束方式）", parameters: [
            "type": "object", "required": ["status", "message"],
            "properties": [
                "status": ["type": "string", "enum": ["draftReady", "needLogin", "failed"]],
                "message": ["type": "string"],
                "draft_url": ["type": "string"],
            ],
        ]),
    ]

    /// 执行一次分发任务
    public func run(goal: String) async throws -> EgoBridge.Finish {
        var messages: [ChatMessage] = [
            ChatMessage(role: "system", content: Self.systemPrompt),
            ChatMessage(role: "user", content: goal),
        ]

        for step in 1...maxSteps {
            onEvent?("思考中…（第 \(step) 步）")
            let turn = try await llm.complete(messages: messages, tools: Self.toolDefs)

            switch turn {
            case .text(let t):
                // 模型没有调工具：把话递回去，要求以 finish 收尾
                messages.append(ChatMessage(role: "assistant", content: t))
                messages.append(ChatMessage(role: "user", content: "请调用 finish 工具结束任务，不要输出纯文本。"))
                onEvent?("模型输出文本，已要求其收敛")

            case .toolCalls(let calls):
                messages.append(ChatMessage(role: "assistant", content: nil, tool_calls: calls))
                for call in calls {
                    let outcome = await execute(call)
                    messages.append(ChatMessage(role: "tool", content: outcome, tool_call_id: call.id))
                    if call.function.name == "finish" {
                        let args = parse(call.function.arguments)
                        let f = EgoBridge.Finish(
                            status: (args["status"] as? String) ?? "failed",
                            message: (args["message"] as? String) ?? "",
                            draftURL: args["draft_url"] as? String)
                        onEvent?("任务结束：\(f.status) — \(f.message)")
                        return f
                    }
                }
            }
        }
        return EgoBridge.Finish(status: "failed", message: "超过最大步数（\(maxSteps)）")
    }

    /// 工具执行：映射到 EgoBridge；发布类动作在工具层就不存在，无从违规
    func execute(_ call: ToolCall) async -> String {
        let name = call.function.name
        let args = parse(call.function.arguments)
        onEvent?("▸ \(name)")
        do {
            let payload: String
            switch name {
            case "navigate":
                payload = try await bridge.navigate(url: require(args, "url"))
            case "snapshot":
                payload = try await bridge.snapshot(scope: args["scope"] as? String ?? "full_page")
            case "fill":
                payload = try await bridge.fill(target: require(args, "target"), text: require(args, "text"))
            case "paste_html":
                payload = try await bridge.pasteHTML(
                    target: require(args, "target"),
                    html: require(args, "html"),
                    plainFallback: args["plain"] as? String ?? "")
            case "upload":
                payload = try await bridge.upload(
                    target: require(args, "target"),
                    paths: (args["paths"] as? [String]) ?? [])
            case "evaluate":
                payload = try await bridge.evaluate(js: require(args, "js"))
            case "finish":
                return "{\"ok\":true}" // finish 由 run() 捕获返回
            default:
                throw EgoBridge.BridgeError.toolFailed("未知工具 \(name)")
            }
            // 快照可能很大，压缩空白
            return payload.replacingOccurrences(of: "\n{2,}", with: "\n", options: .regularExpression)
        } catch {
            // 工具失败也回喂给模型，让它自行调整（这正是 agent 相对死脚本的价值）
            return "{\"ok\":false,\"error\":\"\(error.localizedDescription.replacingOccurrences(of: "\"", with: "'"))\"}"
        }
    }

    func require(_ args: [String: Any], _ key: String) throws -> String {
        guard let v = args[key] as? String else {
            throw EgoBridge.BridgeError.toolFailed("缺少参数 \(key)")
        }
        return v
    }

    func parse(_ argsJSON: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(argsJSON.utf8))) as? [String: Any] ?? [:]
    }
}
