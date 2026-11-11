import Foundation

/// Deterministic compose flow; never submits the post.
final class WeiboChannelAdapter: ChannelAdapter {
    let platform: PlatformID = .weibo
    // No verified account-independent ceiling; actual page acceptance is checked below.
    let capabilities = ChannelCapabilities(usesTitle: true, maximumImages: .max,
        entryURL: "https://weibo.com/", requiresTitle: false)
    private var confirmedImages: [String] = []
    private var pendingImage = false
    private var bodyPasteAttempted = false
    private var opened = false
    private static let editor = ".woo-modal-main .wbpro-layer textarea[placeholder=\"有什么新鲜事想分享给大家？\"]"

    func expectedBody(for request: ChannelRequest) -> String {
        (request.title.isEmpty ? "" : request.title + "\n") + request.body
    }

    func validate(_ request: ChannelRequest) throws {
        guard !request.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChannelFailure(code: .contentUnsupported, stage: .validatingRequest,
                detail: "微博正文必填", recovery: .contentChangeRequired)
        }
    }

    @MainActor
    func execute(request: ChannelRequest, context: ChannelExecutionContext) async throws -> ChannelOutcome {
        do { return try await prepare(request: request, context: context) }
        catch is CancellationError { throw CancellationError() }
        catch { throw context.mapFailure(error) }
    }

    @MainActor
    private func prepare(request: ChannelRequest, context: ChannelExecutionContext) async throws -> ChannelOutcome {
        try context.advance(.validatingRequest)
        try validate(request)
        let uploadPaths = try context.uploadPaths(for: request)
        try context.advance(.openingEditor)
        context.diagnostic("打开微博首页，通过「发微博」进入快捷发布")
        let raw = try await context.bridge.run("""
            // weibo:open-editor
            const current = await page.url();
            if (current !== 'https://weibo.com/') {
                if (\(opened ? "true" : "false") && !/passport|login/.test(current)) throw new Error('微博已离开原首页，请返回原页面后继续');
                if (!\(opened ? "true" : "false")) await page.goto('https://weibo.com/');
            }
            await page.waitForFunction(() => !!document.querySelector('button[title=\"发微博\"]') || !!document.querySelector('\(Self.editor)') ||
                /passport|login/.test(location.hostname + location.pathname) ||
                [...document.querySelectorAll('button,a')].some(el => el.getBoundingClientRect().width > 0 &&
                    /^(登录|立即登录|登录微博)$/.test(el.textContent.trim())), undefined, {timeout:20000});
            const loginRequired = await page.evaluate(() => !document.querySelector('button[title=\"发微博\"]') && !document.querySelector('\(Self.editor)') &&
                (/passport|login/.test(location.hostname + location.pathname) ||
                [...document.querySelectorAll('button,a')].some(el => el.getBoundingClientRect().width > 0 &&
                    /^(登录|立即登录|登录微博)$/.test(el.textContent.trim()))));
            cliLog(JSON.stringify({ok:true,loginRequired}));
            """)
        struct Opening: Decodable { let loginRequired: Bool }
        try context.advance(.checkingLogin)
        if try JSONDecoder().decode(Opening.self, from: Data(raw.utf8)).loginRequired {
            return .waitingForUser(.init(code: .loginRequired, stage: .checkingLogin,
                detail: "请登录微博后继续此渠道", recovery: .loginRequired))
        }
        try context.advance(.openingEditor)
        if !opened {
            // Set before the click: an uncertain click must not reopen another composer on resume.
            opened = true
            _ = try await context.bridge.run("""
                // weibo:open-quick-publish
                const existing = await page.evaluate(() => document.querySelectorAll('\(Self.editor)').length);
                if (existing === 0) {
                    await page.click('button[title="发微博"]', {label:'打开微博快捷发布'});
                    await page.waitForFunction(() => {
                        const editors = document.querySelectorAll('\(Self.editor)');
                        return editors.length === 1 && document.activeElement === editors[0];
                    }, undefined, {timeout:10000});
                }
                cliLog(JSON.stringify({ok:true}));
                """)
        }
        let panelRaw = try await context.bridge.run("""
            // weibo:check-quick-publish
            const present = await page.evaluate(() => {
                const editors = document.querySelectorAll('\(Self.editor)');
                return editors.length === 1 && editors[0].getBoundingClientRect().width > 0 &&
                    editors[0].closest('.wbpro-layer')?.querySelector('.wbpro-layer-tit-text')?.textContent.trim() === '快捷发布';
            });
            cliLog(JSON.stringify({ok:true,present}));
            """)
        struct Panel: Decodable { let present: Bool }
        guard try JSONDecoder().decode(Panel.self, from: Data(panelRaw.utf8)).present else {
            throw ChannelFailure(code: .editorUnavailable, stage: .openingEditor,
                detail: "微博快捷发布面板已关闭或不唯一，请检查原页面后继续；不会重新打开或重复填写", recovery: .inspectionRequired)
        }
        let expected = expectedBody(for: request)
        try context.advance(.fillingContent)
        let initial = try await read(context.bridge)
        try check(initial, expected: expected, allowEmpty: true, stage: .fillingContent)
        try validateImages(initial.images)
        if initial.body.isEmpty {
            guard !bodyPasteAttempted else { throw failure("上次正文粘贴结果未知，请检查页面；不会重复粘贴") }
            bodyPasteAttempted = true
            _ = try await ClipboardPasteService.withTextPaste(expected) {
                try await context.bridge.run("""
                    // weibo:paste-body
                    \(Self.ensureFocus)
                    await page.keyboard.press('Meta+V');
                    cliLog(JSON.stringify({ok:true}));
                    """)
            }
        }
        try check(try await read(context.bridge), expected: expected, allowEmpty: false, stage: .fillingContent)
        context.diagnostic("微博完整正文已回读核对")
        try context.advance(.uploadingAssets)
        if !request.assets.isEmpty {
            let clipboard = try ImageClipboardSession.acquire()
            defer { clipboard.restore() }
            for index in request.assets.indices {
                try Task.checkCancellation()
                let state = try await read(context.bridge)
                try check(state, expected: expected, allowEmpty: false, stage: .uploadingAssets)
                try validateImages(state.images)
                if index < confirmedImages.count { continue }
                if !pendingImage {
                    try clipboard.writePNG(path: uploadPaths[index])
                    pendingImage = true
                    _ = try await context.bridge.run("""
                        // weibo:paste-image
                        \(Self.ensureFocus)
                        await page.keyboard.press('Meta+V');
                        cliLog(JSON.stringify({ok:true}));
                        """)
                }
                _ = try await context.bridge.run("""
                    // weibo:wait-images
                    await page.waitForFunction(count => {
                        const state = (() => { \(Self.readSource) })();
                        return state.images.length === count && state.images.every(i => i.ready) && !state.busy;
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
                detail: "微博尚不允许发布此内容，请检查账号字数限制或页面提示", recovery: .contentChangeRequired)
        }
        return .readyForReview(message: "微博文本及 \(request.assets.count) 张图片已核对，请检查并亲手发布")
    }

    struct Image: Decodable { let identity: String; let ready: Bool }
    struct State: Decodable { let body: String; let images: [Image]; let busy: Bool; let rejected: Bool; let accepted: Bool }
    func validateImages(_ images: [Image]) throws {
        guard images.count >= confirmedImages.count,
              Array(images.prefix(confirmedImages.count).map(\.identity)) == confirmedImages,
              images.prefix(confirmedImages.count).allSatisfy(\.ready),
              images.count == confirmedImages.count + (pendingImage ? 1 : 0) else {
            throw failure("微博附件已变化或上次粘贴结果未知，请检查页面；不会重复粘贴", stage: .uploadingAssets)
        }
    }
    func check(_ state: State, expected: String, allowEmpty: Bool, stage: ChannelStage = .verifyingContent) throws {
        guard !state.rejected else {
            throw ChannelFailure(code: .contentUnsupported, stage: stage,
                detail: "微博编辑器未接受当前内容，请检查账号限制或页面错误", recovery: .contentChangeRequired)
        }
        func lines(_ s: String) -> String { s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n") }
        guard lines(state.body) == lines(expected) || (allowEmpty && state.body.isEmpty) else {
            throw failure(allowEmpty
                ? "微博快捷发布面板已有不同的草稿，本次尝试尚未填写或上传。请检查快捷发布面板中的草稿后继续；现有内容已保留"
                : "微博文本与提交内容不一致，已保留现有内容，请检查页面后继续", stage: stage)
        }
    }
    private func failure(_ detail: String, stage: ChannelStage = .verifyingContent) -> ChannelFailure {
        .init(code: .verificationFailed, stage: stage, detail: detail, recovery: .inspectionRequired)
    }
    private func read(_ bridge: EgoBridge) async throws -> State {
        struct Result: Decodable { let value: State }
        let raw = try await bridge.run("""
            // weibo:read-page
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
        if (location.origin !== 'https://weibo.com' || location.pathname !== '/') throw new Error('微博已离开首页');
        const editors = document.querySelectorAll('\(editor)');
        const editor = editors[0];
        if (editors.length !== 1 || !editor.getBoundingClientRect().width) throw new Error('微博正文框不可操作或不唯一');
        const panel = editor.closest('.wbpro-layer');
        if (panel?.querySelector('.wbpro-layer-tit-text')?.textContent.trim() !== '快捷发布') throw new Error('微博快捷发布面板结构变化');
        const root = editor.closest('div[class^="_box_"]');
        if (!root || !root.querySelector('input[type="file"]')) throw new Error('微博发布卡片结构变化');
        const visible = el => el.getBoundingClientRect().width > 0 && el.getBoundingClientRect().height > 0;
        const attachments = [...root.querySelectorAll('div[class^="_picbed_"]')].filter(el => !el.querySelector('input[type="file"]'));
        const images = attachments.map(el => {
            const img = el.querySelector('img');
            let identity = '';
            if (img) {
                const url = new URL(img.src, location.href);
                if (url.protocol === 'https:' && /(^|\\.)sinaimg\\.cn$/.test(url.hostname)) identity = url.origin + url.pathname;
            }
            return {identity, ready: !!identity && img.complete && img.naturalWidth > 0 && !el.querySelector('.woo-spinner-main')};
        });
        const buttons = [...root.querySelectorAll('button')].filter(el => el.textContent.trim() === '发送');
        if (buttons.length !== 1) throw new Error('微博发送按钮结构变化');
        const rejected = [...root.querySelectorAll('[role="alert"], [class*="_error_"], [class*="_fail_"]')]
            .some(el => visible(el) && el.textContent.trim().length > 0);
        return {body:editor.value, images, busy:attachments.some(el => !!el.querySelector('.woo-spinner-main')),
            rejected, accepted:!buttons[0].disabled && buttons[0].getAttribute('aria-disabled') !== 'true' &&
                !buttons[0].className.includes('disabled') && !editor.validity.tooLong};
        """
}
