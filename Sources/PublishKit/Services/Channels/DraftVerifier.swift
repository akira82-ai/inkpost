import Foundation

/// Checks actual content against the channel's explicit transformation of the complete request.
enum DraftVerifier {
    static func verify(bridge: EgoBridge, result: EgoBridge.Finish, request: ChannelRequest,
                       expectedBody: String, usesTitle: Bool, tagsTarget: String? = nil, verifyImages: Bool = true) async throws {
        func fail(_ detail: String) -> ChannelFailure {
            .init(code: .verificationFailed, stage: .verifyingContent, detail: detail, recovery: .inspectionRequired)
        }
        guard let target = result.bodyTarget else { throw fail("未提供可验证的正文位置") }
        func read(_ selector: String) async throws -> [String: Any] {
            let raw = try await bridge.inspect(target: selector)
            guard let object = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
                  let value = object["value"] as? [String: Any] else { throw fail("无法读取页面内容") }
            return value
        }
        func normalized(_ text: String) -> String {
            text.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let body = try await read(target)
        guard normalized(body["text"] as? String ?? "") == normalized(expectedBody) else { throw fail("正文、标题合并内容或标签与提交内容不一致") }
        if usesTitle {
            guard let target = result.titleTarget else { throw fail("缺少标题校验位置") }
            let title = try await read(target)
            guard normalized(title["text"] as? String ?? "") == normalized(request.title) else { throw fail("标题未完整填写") }
        }
        if let tagsTarget {
            let tags = try await read(tagsTarget)
            guard normalized(tags["text"] as? String ?? "") == normalized(request.tagText) else { throw fail("标签未完整填写") }
        }
        if verifyImages && !request.assets.isEmpty {
            guard let target = result.imageTarget else { throw fail("缺少图片校验位置") }
            let images = try await read(target)
            guard max(images["files"] as? Int ?? 0, images["images"] as? Int ?? 0) == request.assets.count else { throw fail("图片数量不一致") }
        }
    }
}
