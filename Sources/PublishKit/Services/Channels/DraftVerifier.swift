import Foundation

enum DraftVerifier {
    static func verify(bridge: EgoBridge, result: EgoBridge.Finish, title: String, body: String, imageCount: Int, usesTitle: Bool) async throws {
        guard let target = result.bodyTarget else { throw EgoBridge.BridgeError.toolFailed("未提供可验证的正文位置，请手工检查") }
        func read(_ selector: String) async throws -> [String: Any] {
            let raw = try await bridge.inspect(target: selector)
            guard let object = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any], let value = object["value"] as? [String: Any] else { throw EgoBridge.BridgeError.toolFailed("无法校验页面内容") }
            return value
        }
        func normalized(_ text: String) -> String { text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined() }
        let content = try await read(target)
        guard normalized(content["text"] as? String ?? "").contains(normalized(body)) else { throw EgoBridge.BridgeError.toolFailed("正文与提交内容不一致，请手工检查") }
        if usesTitle {
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

}
