import Foundation

/// Deterministic compose flow; never submits the post.
final class BonjourChannelAdapter: ChannelAdapter {
    let platform: PlatformID = .bonjour
    // No verified account-independent ceiling; actual page acceptance is checked below.
    let capabilities = ChannelCapabilities(usesTitle: true, maximumImages: .max,
        entryURL: "https://bonjour.bio/", requiresTitle: false, maximumBodyCharacters: 5000)
    private var retryResetNeeded = false
    private var confirmedImages: [String] = []
    private var pendingImage = false
    private var bodyPasteAttempted = false
    private var opened = false
    private static let editor = "[data-community-post-composer-dialog] textarea[data-community-post-composer-input]"

    func expectedBody(for request: ChannelRequest) -> String {
        (request.title.isEmpty ? "" : request.title + "\n") + request.body
    }

    func validate(_ request: ChannelRequest) throws {
        guard !request.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              expectedBody(for: request).utf16.count <= 5000 else {
            throw ChannelFailure(code: .contentUnsupported, stage: .validatingRequest,
                detail: "Bonjour 正文必填，标题与正文合计不能超过平台的 5000 字符限制", recovery: .contentChangeRequired)
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
        if context.command == .retry { retryResetNeeded = true }
        try context.advance(.validatingRequest)
        try validate(request)
        let uploadPaths = try context.uploadPaths(for: request)
        try context.advance(.openingEditor)
        context.diagnostic("打开 Bonjour 首页，通过「发帖」进入编辑窗口")
        let raw = try await context.bridge.run("""
            // bonjour:open-editor
            const current = await page.url();
            if (current !== 'https://bonjour.bio/') {
                if (\(opened ? "true" : "false")) throw new Error('Bonjour 已离开原页面，请返回后继续');
                await page.goto('https://bonjour.bio/');
            }
            await page.waitForFunction(() => !!document.querySelector('nav[aria-label="主导航"] a[href="/settings"]') ||
                [...document.querySelectorAll('button,a')].some(el => el.getBoundingClientRect().width > 0 && /^(登录|注册或登录|立即登录)$/.test(el.textContent.trim())), undefined, {timeout:20000});
            const loginRequired = await page.evaluate(() => !document.querySelector('nav[aria-label="主导航"] a[href="/settings"]'));
            cliLog(JSON.stringify({ok:true,loginRequired}));
            """)
        struct Opening: Decodable { let loginRequired: Bool }
        try context.advance(.checkingLogin)
        if try JSONDecoder().decode(Opening.self, from: Data(raw.utf8)).loginRequired {
            return .waitingForUser(.init(code: .loginRequired, stage: .checkingLogin,
                detail: "请登录 Bonjour 后继续此渠道", recovery: .loginRequired))
        }
        try context.advance(.openingEditor)
        if !opened {
            opened = true
            _ = try await context.bridge.run("""
                // bonjour:open-quick-publish
                const existing = await page.evaluate(() => document.querySelectorAll('\(Self.editor)').length);
                if (existing === 0) {
                    await page.click("xpath=//nav[@aria-label='主导航']//button[not(@aria-hidden='true') and normalize-space(.)='发帖']", {label:'打开 Bonjour 发帖'});
                    await page.waitForFunction(() => {
                        const editors = document.querySelectorAll('\(Self.editor)');
                        return editors.length === 1 && document.activeElement === editors[0];
                    }, undefined, {timeout:10000});
                }
                cliLog(JSON.stringify({ok:true}));
                """)
        }
        let panelRaw = try await context.bridge.run("""
            // bonjour:check-quick-publish
            const present = await page.evaluate(() => {
                const editors = document.querySelectorAll('\(Self.editor)');
                return editors.length === 1 && editors[0].getBoundingClientRect().width > 0;
            });
            cliLog(JSON.stringify({ok:true,present}));
            """)
        struct Panel: Decodable { let present: Bool }
        guard try JSONDecoder().decode(Panel.self, from: Data(panelRaw.utf8)).present else {
            throw ChannelFailure(code: .editorUnavailable, stage: .openingEditor,
                detail: "Bonjour 发帖窗口已关闭或不唯一，请检查页面后继续", recovery: .inspectionRequired)
        }
        let expected = expectedBody(for: request)
        try context.advance(.fillingContent)
        var initial = try await read(context.bridge)
        if retryResetNeeded {
            try context.advance(.fillingContent)
            // Use the site's explicit remove controls; never mutate editor state directly.
            _ = try await context.bridge.run("""
                // bonjour:reset-editor
                for (let index = 0; index < \(initial.images.count); index++) {
                    await page.click('[data-community-post-composer-dialog] button[aria-label="删除配图 1"]', {label:'移除 Bonjour 重试图片'});
                    await page.waitForFunction(count => document.querySelectorAll('[data-community-post-composer-dialog] [data-community-media-slide]').length === count, \(initial.images.count) - index - 1, {timeout:10000});
                }
                await page.fill('\(Self.editor)', '');
                cliLog(JSON.stringify({ok:true}));
                """)
            initial = try await read(context.bridge)
            guard initial.body.isEmpty, initial.images.isEmpty else {
                throw ChannelFailure(code: .verificationFailed, stage: .fillingContent,
                    detail: "重试页面未清空，已停止填写", recovery: .inspectionRequired)
            }
            retryResetNeeded = false
        }
        try check(initial, expected: expected, allowEmpty: true, stage: .fillingContent)
        try validateImages(initial.images)
        if initial.body.isEmpty {
            guard !bodyPasteAttempted else { throw failure("上次正文粘贴结果未知，请检查页面；不会重复粘贴") }
            bodyPasteAttempted = true
            _ = try await ClipboardPasteService.withTextPaste(expected) {
                try await context.bridge.run("""
                    // bonjour:paste-body
                    \(Self.ensureFocus)
                    await page.keyboard.press('Meta+V');
                    cliLog(JSON.stringify({ok:true}));
                    """)
            }
        }
        try check(try await read(context.bridge), expected: expected, allowEmpty: false, stage: .fillingContent)
        context.diagnostic("Bonjour 完整正文已回读核对")
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
                        // bonjour:paste-image
                        \(Self.ensureFocus)
                        await page.keyboard.press('Meta+V');
                        cliLog(JSON.stringify({ok:true}));
                        """)
                }
                _ = try await context.bridge.run("""
                    // bonjour:wait-images
                    await page.waitForFunction(count => {
                        const state = (() => { \(Self.readSource) })();
                        return state.images.length === count && state.images.every(i => i.ready) && !state.busy;
                    }, \(index + 1), {timeout:60000});
                    cliLog(JSON.stringify({ok:true}));
                    """)
                let uploaded = try await read(context.bridge)
                try validateImages(uploaded.images)
                guard uploaded.images.count == index + 1, uploaded.images.allSatisfy(\.ready), !uploaded.busy else {
                    throw failure("图片尚未完成载入", stage: .uploadingAssets)
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
            throw failure("图片数量或载入状态不完整")
        }
        guard final.accepted else {
            throw ChannelFailure(code: .contentUnsupported, stage: .verifyingContent,
                detail: "Bonjour 尚不允许发布此内容，请检查分区、账号限制或页面提示", recovery: .contentChangeRequired)
        }
        return .readyForReview(message: "Bonjour 文本及 \(request.assets.count) 张图片已核对，请检查并亲手发布")
    }

    struct Image: Decodable { let identity: String; let ready: Bool }
    struct State: Decodable { let body: String; let images: [Image]; let busy: Bool; let rejected: Bool; let accepted: Bool }
    func validateImages(_ images: [Image]) throws {
        guard images.count >= confirmedImages.count,
              Array(images.prefix(confirmedImages.count).map(\.identity)) == confirmedImages,
              images.prefix(confirmedImages.count).allSatisfy(\.ready),
              images.count == confirmedImages.count + (pendingImage ? 1 : 0) else {
            throw failure("Bonjour 附件已变化或上次粘贴结果未知，请检查页面；不会重复粘贴", stage: .uploadingAssets)
        }
    }
    func check(_ state: State, expected: String, allowEmpty: Bool, stage: ChannelStage = .verifyingContent) throws {
        guard !state.rejected else {
            throw ChannelFailure(code: .contentUnsupported, stage: stage,
                detail: "Bonjour 编辑器未接受当前内容，请检查账号限制或页面错误", recovery: .contentChangeRequired)
        }
        func lines(_ s: String) -> String { s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n") }
        guard lines(state.body) == lines(expected) || (allowEmpty && state.body.isEmpty) else {
            throw failure(allowEmpty
                ? "Bonjour 发帖窗口已有不同的草稿，本次尝试尚未填写或上传。请检查快捷发布面板中的草稿后继续；现有内容已保留"
                : "Bonjour 文本与提交内容不一致，已保留现有内容，请检查页面后继续", stage: stage)
        }
    }
    private func failure(_ detail: String, stage: ChannelStage = .verifyingContent) -> ChannelFailure {
        .init(code: .verificationFailed, stage: stage, detail: detail, recovery: .inspectionRequired)
    }
    private func read(_ bridge: EgoBridge) async throws -> State {
        struct Result: Decodable { let value: State }
        let raw = try await bridge.run("""
            // bonjour:read-page
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
        if (location.origin !== 'https://bonjour.bio' || location.pathname !== '/') throw new Error('Bonjour 已离开首页');
        const editors = document.querySelectorAll('\(editor)');
        const editor = editors[0];
        if (editors.length !== 1 || !editor.getBoundingClientRect().width) throw new Error('Bonjour 正文框不可操作或不唯一');
        const root = editor.closest('[data-community-post-composer-dialog]');
        const tiles = [...root.querySelectorAll('[data-community-media-slide]')];
        if (tiles.some(el => el.getAttribute('data-media-kind') !== 'image') || root.querySelector('video')) throw new Error('Bonjour 存在非图片附件，请检查页面');
        const images = tiles.map(el => {
            const img = el.querySelector('img');
            const button = el.querySelector('[data-community-image-open]');
            let identity = '';
            if (img) {
                const url = new URL(img.src, location.href);
                if (url.protocol === 'https:' && url.hostname === 'cdn.bonjour.bio') identity = url.origin + url.pathname;
                else if (url.protocol === 'blob:' && url.origin === location.origin) identity = url.href;
            }
            return {identity, ready: !!identity && img.complete && img.naturalWidth > 0 && button?.getAttribute('data-community-image-status') === 'loaded'};
        });
        const buttons = root.querySelectorAll('button[type="submit"][aria-label="发布"]');
        if (buttons.length !== 1) throw new Error('Bonjour 发布按钮结构变化');
        const visible = el => el.getBoundingClientRect().width > 0 && el.getBoundingClientRect().height > 0;
        const rejected = [...root.querySelectorAll('[role="alert"]')].some(el => visible(el) && el.textContent.trim().length > 0) ||
            !!root.querySelector('[data-community-image-status="error"]');
        return {body:editor.value, images, busy:images.some(image => !image.ready), rejected,
            accepted:!buttons[0].disabled && buttons[0].getAttribute('aria-disabled') !== 'true' && editor.validity.valid};
        """
}
