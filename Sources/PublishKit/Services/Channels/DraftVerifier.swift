import Foundation

/// Exact readback for the local fixture's fixed fields.
enum DraftVerifier {
    static func read(bridge: EgoBridge, target: String) async throws -> [String: Any] {
        let raw = try await bridge.inspect(target: target)
        guard let object = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
              let value = object["value"] as? [String: Any] else {
            throw failure("无法读取模拟页面内容")
        }
        return value
    }
    static func verify(bridge: EgoBridge, request: ChannelRequest) async throws {
        for (target, expected) in [("#title", request.title), ("#editor", request.body), ("#tags", request.tagText)] {
            let value = try await read(bridge: bridge, target: target)
            guard value["text"] as? String == expected else { throw failure("模拟页面字段未完整填写：\(target)") }
        }
        let images = try await read(bridge: bridge, target: "#files")
        guard images["files"] as? Int == request.assets.count else { throw failure("图片数量不一致") }
    }
    private static func failure(_ detail: String) -> ChannelFailure {
        .init(code: .verificationFailed, stage: .verifyingContent, detail: detail, recovery: .inspectionRequired)
    }
}
