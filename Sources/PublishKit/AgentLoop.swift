import Foundation

// MARK: - LLM 会话协议（OpenAI 兼容 /chat/completions）

public struct LLMConfig: Codable {
    public var baseURL: String   // 例：https://open.bigmodel.cn/api/paas/v4
    public var apiKey: String
    public var model: String     // 例：glm-4.6 / glm-4.5-flash
    public init(baseURL: String, apiKey: String, model: String) {
        self.baseURL = baseURL; self.apiKey = apiKey; self.model = model
    }
}

public struct ChatMessage: Codable {
    public var role: String          // system | user | assistant | tool
    public var content: String?
    public var tool_calls: [ToolCall]?
    public var tool_call_id: String?

    public init(role: String, content: String? = nil, tool_calls: [ToolCall]? = nil, tool_call_id: String? = nil) {
        self.role = role; self.content = content; self.tool_calls = tool_calls; self.tool_call_id = tool_call_id
    }
}

public struct ToolCall: Codable {
    public var id: String
    public var type: String = "function"
    public var function: FunctionCall
    public init(id: String, function: FunctionCall) {
        self.id = id; self.function = function
    }
    public struct FunctionCall: Codable {
        public var name: String
        public var arguments: String // JSON 字符串
        public init(name: String, arguments: String) {
            self.name = name; self.arguments = arguments
        }
    }
}

/// 模型一轮回执：要么说话，要么调工具
public enum AssistantTurn {
    case text(String)
    case toolCalls([ToolCall])
}

/// LLM 会话抽象：真实 HTTP 客户端与测试假模型都实现它
public protocol LLMSession {
    func complete(messages: [ChatMessage], tools: [ToolDef]) async throws -> AssistantTurn
}

// MARK: - 工具定义（给模型看的 schema）

public struct ToolDef: Encodable {
    public var type: String = "function"
    public var function: FunctionDef
    public init(name: String, description: String, parameters: [String: Any]) {
        self.function = .init(name: name, description: description, parameters: parameters)
    }
    public struct FunctionDef: Encodable {
        public var name: String
        public var description: String
        public var parameters: [String: Any]
        // 手工编码 parameters（OpenAI JSON schema），避免 Any 的 Codable 麻烦
        enum CodingKeys: String, CodingKey { case name, description, parameters }
        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(name, forKey: .name)
            try c.encode(description, forKey: .description)
            try c.encode(JSONValue(parameters), forKey: .parameters)
        }
        public init(name: String, description: String, parameters: [String: Any]) {
            self.name = name; self.description = description; self.parameters = parameters
        }
    }
    // 编码时带 type
    enum TypeKeys: String, CodingKey { case type, function }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: TypeKeys.self)
        try c.encode(type, forKey: .type)
        try c.encode(function, forKey: .function)
    }
    public init(type: String = "function", function: FunctionDef) {
        self.type = type; self.function = function
    }
}

/// 极简 JSON 值编码器（够用即可）
struct JSONValue: Encodable {
    let any: Any
    init(_ any: Any) { self.any = any }
    func encode(to encoder: Encoder) throws {
        switch any {
        case let s as String:
            var c = encoder.singleValueContainer(); try c.encode(s)
        case let n as Int:
            var c = encoder.singleValueContainer(); try c.encode(n)
        case let n as Double:
            var c = encoder.singleValueContainer(); try c.encode(n)
        case let b as Bool:
            var c = encoder.singleValueContainer(); try c.encode(b)
        case let arr as [Any]:
            var unkeyed = encoder.unkeyedContainer()
            for item in arr { try unkeyed.encode(JSONValue(item)) }
        case let dict as [String: Any]:
            var keyed = encoder.container(keyedBy: JSONKey.self)
            for (k, v) in dict { try keyed.encode(JSONValue(v), forKey: JSONKey(k)) }
        default:
            var c = encoder.singleValueContainer(); try c.encodeNil()
        }
    }
    struct JSONKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ s: String) { stringValue = s }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}
