import Foundation

/// Deterministic local fixture workflow; never clicks the publication control.
final class FixtureChannelAdapter: ChannelAdapter {
    let platform: PlatformID = .simFixture
    let capabilities = ChannelCapabilities(usesTitle: true, maximumImages: 6, isArticle: true)
    private var opened = false
    private var uploadStarted = false

    @MainActor
    func execute(request: ChannelRequest, context: ChannelExecutionContext) async throws -> ChannelOutcome {
        try PlatformRules.validate(request, capabilities: capabilities)
        let uploadPaths = try context.uploadPaths(for: request)
        let bridge = context.bridge
        try context.advance(.openingEditor)
        if !opened {
            _ = try await bridge.navigate(url: Resources.url("fixture-page", ext: "html", sub: "Fixtures").absoluteString)
            opened = true
        }
        try context.advance(.fillingContent)
        // Preserve an existing matching field; conflicts require inspection, never overwrite.
        for (target, expected) in [("#title", request.title), ("#editor", request.body), ("#tags", request.tagText)] {
            let current = try await DraftVerifier.read(bridge: bridge, target: target)["text"] as? String ?? ""
            guard current.isEmpty || current == expected else {
                throw ChannelFailure(code: .verificationFailed, stage: .fillingContent,
                    detail: "模拟页面已有不同内容：\(target)", recovery: .inspectionRequired)
            }
            if current != expected { _ = try await bridge.fill(target: target, text: expected) }
        }
        if !request.assets.isEmpty {
            try context.advance(.uploadingAssets)
            if !uploadStarted {
                uploadStarted = true
                _ = try await bridge.upload(target: "#files", paths: uploadPaths)
            }
        }
        try context.advance(.verifyingContent)
        try await DraftVerifier.verify(bridge: bridge, request: request)
        return .readyForReview(message: "模拟平台已填好")
    }
}
