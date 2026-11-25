import Foundation

/// Deterministic compose flow; never submits the post.
final class XChannelAdapter: ChannelAdapter {
    let platform: PlatformID = .x
    let capabilities = ChannelCapabilities(usesTitle: false, maximumImages: 4,
        entryURL: "https://x.com/home", requiresTitle: false, maximumBodyCharacters: 1899)
    private var confirmedImages: [String] = []
    private var pendingImage = false
    private static let editor = "[role=\"dialog\"] textarea"
    private static let attachments = "[role=\"dialog\"] [data-media-tile]"

    func expectedBody(for request: ChannelRequest) -> String {
        (request.title.isEmpty ? "" : request.title + "\n") + request.body
    }

    func validate(_ request: ChannelRequest) throws {
        guard !request.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              expectedBody(for: request).count <= 1899, request.assets.count <= 4 else {
            throw ChannelFailure(code: .contentUnsupported, stage: .validatingRequest,
                detail: "X 正文必填；标题和正文合计最多 1899 字，图片最多 4 张", recovery: .contentChangeRequired)
        }
    }

    @MainActor
    func execute(request: ChannelRequest, context: ChannelExecutionContext) async throws -> ChannelOutcome {
        try context.advance(.validatingRequest)
        try validate(request)
        let uploadPaths = try context.uploadPaths(for: request)
        try context.advance(.openingEditor)
        let raw = try await context.bridge.run("""
            // x:open-editor
            const current = await page.url();
            if (current !== 'https://x.com/compose/post' && current !== 'https://x.com/home') await page.goto('https://x.com/home');
            await page.waitForFunction(() => location.pathname.includes('/login') || location.pathname.includes('/flow/') ||
                !!document.querySelector('\(Self.editor)') || !!document.querySelector('a[href="/compose/post"]'), undefined, {timeout:20000});
            const loginRequired = await page.evaluate(() => location.pathname.includes('/login') || location.pathname.includes('/flow/'));
            cliLog(JSON.stringify({ok:true,loginRequired}));
            """)
        struct Opening: Decodable { let loginRequired: Bool }
        try context.advance(.checkingLogin)
        if try JSONDecoder().decode(Opening.self, from: Data(raw.utf8)).loginRequired {
            return .waitingForUser(.init(code: .loginRequired, stage: .checkingLogin,
                detail: "请登录 X 后继续此渠道", recovery: .loginRequired))
        }
        try context.advance(.openingEditor)
        _ = try await context.bridge.run("""
            // x:open-compose
            const existing = await page.evaluate(() => document.querySelectorAll('\(Self.editor)').length);
            if (existing === 0) {
                await page.click('a[href="/compose/post"]', {label:'打开 X 发帖窗口'});
            }
            await page.waitForFunction(() => {
                const editors = document.querySelectorAll('\(Self.editor)');
                return editors.length === 1 && editors[0].checkVisibility();
            }, undefined, {timeout:10000});
            cliLog(JSON.stringify({ok:true}));
            """)
        let expected = expectedBody(for: request)
        var initial = try await read(context.bridge)
        do {
            try context.advance(.fillingContent)
            _ = try await context.bridge.run("""
                // x:clear-editor
                for (let index = 0; index < \(initial.images.count); index++) {
                    await page.click('\(Self.attachments) button[data-remove-media] >> nth=0', {label:'清空 X 原有图片'});
                    await page.waitForFunction(count => document.querySelectorAll('\(Self.attachments)').length === count,
                        \(initial.images.count) - index - 1, {timeout:10000});
                }
                await page.fill('\(Self.editor)', '');
                cliLog(JSON.stringify({ok:true}));
                """)
            initial = try await read(context.bridge)
            guard initial.body.isEmpty, initial.images.isEmpty else {
                throw ChannelFailure(code: .verificationFailed, stage: .fillingContent,
                    detail: "页面未清空，已停止填写", recovery: .inspectionRequired)
            }
            confirmedImages = []; pendingImage = false
        }
        try check(initial, expected: expected, allowEmpty: true)
        try validateImages(initial.images)
        try context.advance(.fillingContent)
        if initial.body.isEmpty {
            _ = try await ClipboardPasteService.withTextPaste(expected) {
                try await context.bridge.run("""
                    // x:paste-body
                    \(Self.ensureFocus)
                    await page.keyboard.press('Meta+V');
                    cliLog(JSON.stringify({ok:true}));
                    """)
            }
        }
        try check(try await read(context.bridge), expected: expected, allowEmpty: false)
        try context.advance(.uploadingAssets)
        if !request.assets.isEmpty {
            let clipboard = try ImageClipboardSession.acquire()
            defer { clipboard.restore() }
            for index in request.assets.indices {
                try Task.checkCancellation()
                let state = try await read(context.bridge)
                try check(state, expected: expected, allowEmpty: false)
                try validateImages(state.images)
                if index < confirmedImages.count { continue }
                if !pendingImage {
                    try clipboard.writePNG(path: uploadPaths[index])
                    pendingImage = true
                    _ = try await context.bridge.run("""
                        // x:paste-image
                        \(Self.ensureFocus)
                        await page.keyboard.press('Meta+V');
                        cliLog(JSON.stringify({ok:true}));
                        """)
                }
                _ = try await context.bridge.run("""
                    // x:wait-images
                    await page.waitForFunction(count => {
                        const state = (() => { \(Self.readSource) })();
                        return state.images.length === count && state.images.every(i => i.ready) && !state.busy && state.accepted;
                    }, \(index + 1), {timeout:60000});
                    cliLog(JSON.stringify({ok:true}));
                    """)
                let uploaded = try await read(context.bridge)
                try validateImages(uploaded.images)
                guard uploaded.images.count == index + 1, uploaded.images.allSatisfy(\.ready), !uploaded.busy else {
                    throw failure("图片尚未完成上传", stage: .uploadingAssets)
                }
                confirmedImages = uploaded.images.map(\.identity)
                pendingImage = false
                try context.progress(completed: index + 1, total: request.assets.count)
            }
        }
        try context.advance(.verifyingContent)
        let final = try await read(context.bridge)
        try check(final, expected: expected, allowEmpty: false)
        try validateImages(final.images)
        guard final.images.count == request.assets.count, final.images.allSatisfy(\.ready), !final.busy, !pendingImage else {
            throw failure("图片数量或上传状态不完整")
        }
        guard final.accepted else {
            throw ChannelFailure(code: .contentUnsupported, stage: .verifyingContent,
                detail: "X 尚不允许发布此内容，请检查账号字数限制或页面提示", recovery: .contentChangeRequired)
        }
        return .readyForReview(message: "X 文本及 \(request.assets.count) 张图片已核对，请检查并亲手发布")
    }

    struct Image: Decodable { let identity: String; let ready: Bool }
    struct State: Decodable { let body: String; let images: [Image]; let busy: Bool; let rejected: Bool; let accepted: Bool }
    func validateImages(_ images: [Image]) throws {
        guard images.count >= confirmedImages.count,
              Array(images.prefix(confirmedImages.count).map(\.identity)) == confirmedImages,
              images.prefix(confirmedImages.count).allSatisfy(\.ready),
              images.count == confirmedImages.count + (pendingImage ? 1 : 0) else {
            throw failure("X 附件已变化或上次粘贴结果未知，请检查页面；不会重复粘贴", stage: .uploadingAssets)
        }
    }
    func check(_ state: State, expected: String, allowEmpty: Bool) throws {
        guard !state.rejected else {
            throw ChannelFailure(code: .contentUnsupported, stage: .verifyingContent,
                detail: "X 编辑器未接受当前内容，请检查账号限制或页面错误", recovery: .contentChangeRequired)
        }
        func lines(_ s: String) -> String { s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n") }
        guard lines(state.body) == lines(expected) || (allowEmpty && state.body.isEmpty) else {
            throw failure("X 文本与提交内容不一致，已保留现有内容")
        }
    }
    private func failure(_ detail: String, stage: ChannelStage = .verifyingContent) -> ChannelFailure {
        .init(code: .verificationFailed, stage: stage, detail: detail, recovery: .inspectionRequired)
    }
    private func read(_ bridge: EgoBridge) async throws -> State {
        struct Result: Decodable { let value: State }
        let raw = try await bridge.run("""
            // x:read-page
            const value = await page.evaluate(() => { \(Self.readSource) });
            cliLog(JSON.stringify({ok:true,value}));
            """)
        return try JSONDecoder().decode(Result.self, from: Data(raw.utf8)).value
    }
    private static let ensureFocus = """
        const focused = await page.evaluate(() => document.activeElement === document.querySelector('\(editor)'));
        if (!focused) await page.focus('\(editor)');
        """
    private static let readSource = """
        if (location.origin !== 'https://x.com' || location.pathname !== '/compose/post') throw new Error('X 已离开撰写页面');
        const editors = document.querySelectorAll('\(editor)');
        const editor = editors[0];
        if (editors.length !== 1 || !editor.checkVisibility()) throw new Error('X 正文框不可操作或不唯一');
        const root = editor.closest('[role="dialog"]');
        const visible = el => el.checkVisibility({checkOpacity:true, checkVisibilityCSS:true});
        const tiles = [...root.querySelectorAll('[data-media-tile]')];
        const images = tiles.map(tile => {
            const imgs = tile.querySelectorAll('img');
            if (imgs.length !== 1 || tile.querySelector('video') || tile.querySelectorAll('button[data-remove-media]').length !== 1)
                throw new Error('X 附件结构变化或存在非图片附件');
            const img = imgs[0];
            return {identity:tile.getAttribute('data-media-tile') + '|' + img.src,
                ready:img.complete && img.naturalWidth > 0};
        });
        const buttons = [...root.querySelectorAll('form button')].filter(button => visible(button) && /^(发帖|Post)$/.test(button.textContent.trim()));
        if (buttons.length !== 1) throw new Error('X 发帖按钮不可唯一确认');
        const busy = [...root.querySelectorAll('[role="progressbar"], [aria-busy="true"]')].some(visible);
        const rejected = [...root.querySelectorAll('[role="alert"]')].some(el => visible(el) && el.textContent.length > 0) ||
            tiles.some(tile => [...tile.querySelectorAll('button[aria-label]')].some(button => visible(button) && /^(重试|Retry) /.test(button.getAttribute('aria-label'))));
        return {body:editor.value, images, busy, rejected,
            accepted:!buttons[0].disabled && buttons[0].getAttribute('aria-disabled') !== 'true' && editor.validity.valid};
        """
}
