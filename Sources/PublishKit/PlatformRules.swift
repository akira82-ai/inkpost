import Foundation

/// Domain validation shared by the dispatch boundary; channel workflows live in adapters.
public enum PlatformRules {
    public static func validate(_ request: ChannelRequest, capabilities: ChannelCapabilities) throws {
        if capabilities.requiresTitle && request.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ChannelFailure(code: .contentUnsupported, stage: .validatingRequest,
                                 detail: "请填写标题", recovery: .contentChangeRequired)
        }
        if request.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ChannelFailure(code: .contentUnsupported, stage: .validatingRequest,
                                 detail: "请填写正文", recovery: .contentChangeRequired)
        }
        if let limit = capabilities.maximumTitleCharacters, request.title.count > limit {
            throw ChannelFailure(code: .contentUnsupported, stage: .validatingRequest,
                                 detail: "标题最多 \(limit) 字，当前 \(request.title.count) 字", recovery: .contentChangeRequired)
        }
        if let limit = capabilities.maximumBodyCharacters, request.taggedBody.count > limit {
            throw ChannelFailure(code: .contentUnsupported, stage: .validatingRequest,
                                 detail: "正文（含标签和换行）最多 \(limit) 字，当前 \(request.taggedBody.count) 字", recovery: .contentChangeRequired)
        }
        if request.assets.count > capabilities.maximumImages {
            throw ChannelFailure(code: .contentUnsupported, stage: .validatingRequest,
                                 detail: "图片超过渠道上限（最多 \(capabilities.maximumImages) 张）", recovery: .contentChangeRequired)
        }
    }
}
