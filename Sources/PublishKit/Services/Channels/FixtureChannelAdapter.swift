import Foundation

/// Deterministic local fixture workflow; never clicks the publication control.
final class FixtureChannelAdapter: ChannelAdapter {
    let platform: PlatformID = .simFixture
    let capabilities = ChannelCapabilities(usesTitle: true, maximumImages: 6, isArticle: true, requiresTitle: true)
    private var opened = false

    func validate(_ request: ChannelRequest) throws {
        if capabilities.requiresTitle && request.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ChannelFailure(code: .contentUnsupported, stage: .validatingRequest,
                                 detail: "请填写标题", recovery: .contentChangeRequired)
        }
        if request.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ChannelFailure(code: .contentUnsupported, stage: .validatingRequest,
                                 detail: "请填写正文", recovery: .contentChangeRequired)
        }
        if request.assets.count > capabilities.maximumImages {
            throw ChannelFailure(code: .contentUnsupported, stage: .validatingRequest,
                                 detail: "图片超过渠道上限（最多 \(capabilities.maximumImages) 张）", recovery: .contentChangeRequired)
        }
    }

    @MainActor
    func execute(request: ChannelRequest, context: ChannelExecutionContext) async throws -> ChannelOutcome {
        try context.advance(.validatingRequest)
        try validate(request)
        let uploadPaths = try context.uploadPaths(for: request)
        let bridge = context.bridge
        try context.advance(.openingEditor)
        if !opened {
            _ = try await bridge.navigate(url: Resources.url("fixture-page", ext: "html", sub: "Fixtures").absoluteString)
            opened = true
        }
        try context.advance(.fillingContent)
        _ = try await bridge.fill(target: "#title", text: "")
        _ = try await bridge.fill(target: "#editor", text: "")
        _ = try await bridge.upload(target: "#files", paths: [])
        for target in ["#title", "#editor", "#files"] {
            let state = try await DraftVerifier.read(bridge: bridge, target: target)
            let empty = target == "#files" ? (state["files"] as? Int == 0) : (state["text"] as? String == "")
            guard empty else {
                throw ChannelFailure(code: .verificationFailed, stage: .fillingContent,
                    detail: "模拟页面未清空：\(target)", recovery: .inspectionRequired)
            }
        }
        _ = try await bridge.fill(target: "#title", text: request.title)
        _ = try await bridge.fill(target: "#editor", text: request.body)
        if !request.assets.isEmpty {
            try context.advance(.uploadingAssets)
            _ = try await bridge.upload(target: "#files", paths: uploadPaths)
        }
        try context.advance(.verifyingContent)
        try await DraftVerifier.verify(bridge: bridge, request: request)
        return .readyForReview(message: "模拟平台已填好")
    }
}
