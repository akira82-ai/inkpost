import Foundation

/// Task-scoped inline composer. Never invokes the final Send control.
final class JikeChannelAdapter: ChannelAdapter {
    let platform: PlatformID = .jike
    // No verified platform image/character ceiling: the editor enforces the product's six-asset limit.
    let capabilities = ChannelCapabilities(usesTitle: false, maximumImages: .max,
        entryURL: "https://web.okjike.com/following", requiresTitle: false)
    private static let editor = "form [data-lexical-editor=\"true\"][contenteditable=\"true\"]"
    private var confirmed: [String] = []
    private var pending = false
    private var opened = false

    func expectedBody(for request: ChannelRequest) -> String { request.body }
    func validate(_ request: ChannelRequest) throws {
        guard !request.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChannelFailure(code: .contentUnsupported, stage: .validatingRequest,
                detail: "即刻正文必填", recovery: .contentChangeRequired)
        }
    }

    @MainActor
    func execute(request: ChannelRequest, context: ChannelExecutionContext) async throws -> ChannelOutcome {
        try context.advance(.validatingRequest)
        try validate(request)
        let uploadPaths = try context.uploadPaths(for: request)
        try context.advance(.openingEditor)
        context.diagnostic("打开即刻关注页，定位「分享你的想法…」编辑器")
        let raw = try await context.bridge.run("""
            // jike:open-editor
            const current = await page.url();
            if (current !== 'https://web.okjike.com/following') {
              if (\(opened ? "true" : "false")) throw new Error('即刻已离开原编辑页，请返回原页面后继续');
              await page.goto('https://web.okjike.com/following');
            }
            await page.waitForFunction(() => !!document.querySelector('\(Self.editor)') ||
              /login|signin/.test(location.pathname) || [...document.querySelectorAll('button,a')].some(el =>
                el.getBoundingClientRect().width > 0 && /^(登录|登录即刻|立即登录)$/.test(el.textContent.trim())), undefined, {timeout:20000});
            const loginRequired = await page.evaluate(() => !document.querySelector('\(Self.editor)') &&
              (/login|signin/.test(location.pathname) || [...document.querySelectorAll('button,a')].some(el =>
                el.getBoundingClientRect().width > 0 && /^(登录|登录即刻|立即登录)$/.test(el.textContent.trim()))));
            cliLog(JSON.stringify({ok:true,loginRequired}));
            """)
        struct Opening: Decodable { let loginRequired: Bool }
        try context.advance(.checkingLogin)
        if try JSONDecoder().decode(Opening.self, from: Data(raw.utf8)).loginRequired {
            return .waitingForUser(.init(code: .loginRequired, stage: .checkingLogin,
                detail: "请登录即刻后点击继续，保留当前页面", recovery: .loginRequired))
        }
        opened = true
        let initial = try await read(context.bridge)
        try check(initial, request: request, allowEmpty: true)
        try validateImages(initial.images)
        try context.advance(.fillingContent)
        if initial.body.isEmpty {
            _ = try await ClipboardPasteService.withTextPaste {
                try await context.bridge.run("""
                    // jike:paste-body
                    await page.click('\(Self.editor)', {label:'填写即刻想法正文'});
                    await page.keyboard.paste(\(context.bridge.jsStr(expectedBody(for: request))));
                    cliLog(JSON.stringify({ok:true}));
                    """)
            }
        }
        try check(try await read(context.bridge), request: request, allowEmpty: false)
        try context.advance(.uploadingAssets)
        for index in request.assets.indices {
            try Task.checkCancellation()
            let state = try await read(context.bridge)
            try check(state, request: request, allowEmpty: false)
            try validateImages(state.images)
            if index < confirmed.count { continue }
            if !pending {
                // An interrupted file chooser/upload may already have written; never replay blindly.
                pending = true
                try context.progress(completed: index, total: request.assets.count)
                _ = try await context.bridge.run("""
                    // jike:upload-image
                    const chooserPromise = page.waitForFileChooser({timeout:10000});
                    await page.click('form [title="图片"]', {label:'添加即刻下一张图片'});
                    const chooser = await chooserPromise;
                    await chooser.setFiles(\(context.bridge.jsStr(uploadPaths[index])));
                    cliLog(JSON.stringify({ok:true}));
                    """)
            }
            do {
                _ = try await context.bridge.run("""
                    // jike:wait-images
                    await page.waitForFunction(async expected => {
                      const state = await (async () => { \(Self.readSource) })();
                      return state.images.length === expected && state.images.every(image => image.ready) && state.accepted;
                    }, \(index + 1), {timeout:60000});
                    cliLog(JSON.stringify({ok:true}));
                    """)
            } catch {
                if error is CancellationError || Task.isCancelled { throw CancellationError() }
                throw ChannelFailure(code: .uploadFailed, stage: .uploadingAssets,
                    detail: "即刻第 \(index + 1) 张图片未确认上传完成：\(error.localizedDescription)", recovery: .inspectionRequired)
            }
            let uploaded = try await read(context.bridge)
            try check(uploaded, request: request, allowEmpty: false)
            try validateImages(uploaded.images)
            guard uploaded.images.count == index + 1, uploaded.images.allSatisfy(\.ready) else {
                throw failure("即刻图片尚未完整上传", stage: .uploadingAssets)
            }
            confirmed = uploaded.images.map(\.identity); pending = false
            try context.progress(completed: index + 1, total: request.assets.count)
        }
        try context.advance(.verifyingContent)
        let final = try await read(context.bridge)
        try check(final, request: request, allowEmpty: false)
        try validateImages(final.images)
        guard !pending, final.images.count == request.assets.count, final.images.allSatisfy(\.ready) else {
            throw failure("即刻图片数量或上传状态不完整")
        }
        guard final.accepted else {
            throw ChannelFailure(code: .contentUnsupported, stage: .verifyingContent,
                detail: "即刻尚未允许发送，请检查字数、附件或页面提示", recovery: .contentChangeRequired)
        }
        return .readyForReview(message: "即刻正文及 \(request.assets.count) 张图片已核对，请检查后亲手发送")
    }

    struct Image: Decodable { let identity: String; let ready: Bool }
    struct State: Decodable { let body: String; let images: [Image]; let accepted: Bool; let rejected: Bool }
    func validateImages(_ images: [Image]) throws {
        guard images.count >= confirmed.count,
              Array(images.prefix(confirmed.count).map(\.identity)) == confirmed,
              images.prefix(confirmed.count).allSatisfy(\.ready),
              images.count == confirmed.count + (pending ? 1 : 0) else {
            throw ChannelFailure(code: pending ? .operationResultUnknown : .verificationFailed, stage: .uploadingAssets,
                detail: "即刻附件已变化或上次上传结果未知，已保留现场，不会重复上传", recovery: .inspectionRequired)
        }
    }
    func check(_ state: State, request: ChannelRequest, allowEmpty: Bool) throws {
        guard !state.rejected else {
            throw ChannelFailure(code: .contentUnsupported, stage: .verifyingContent,
                detail: "即刻编辑器报告错误，请检查页面提示", recovery: .contentChangeRequired)
        }
        func lines(_ text: String) -> String { text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n") }
        guard lines(state.body) == lines(expectedBody(for: request)) || (allowEmpty && state.body.isEmpty) else {
            throw failure("即刻正文、空格或段落与任务不一致，已保留原内容")
        }
    }
    private func failure(_ detail: String, stage: ChannelStage = .verifyingContent) -> ChannelFailure {
        .init(code: .verificationFailed, stage: stage, detail: detail, recovery: .inspectionRequired)
    }
    private func read(_ bridge: EgoBridge) async throws -> State {
        struct Result: Decodable { let value: State }
        let raw = try await bridge.run("""
            // jike:read-page
            const value = await page.evaluate(async () => { \(Self.readSource) });
            cliLog(JSON.stringify({ok:true,value}));
            """)
        return try JSONDecoder().decode(Result.self, from: Data(raw.utf8)).value
    }
    static let readSource = """
        if (location.origin !== 'https://web.okjike.com' || location.pathname !== '/following') throw new Error('即刻已离开关注页');
        const editors = [...document.querySelectorAll('\(editor)')];
        if (editors.length !== 1) throw new Error('即刻编辑器缺失或不唯一');
        const editor = editors[0], root = editor.closest('form');
        if (!editor.getBoundingClientRect().width || !root) throw new Error('即刻编辑器不可操作');
        const paragraphs = [...editor.children];
        if (!paragraphs.length || paragraphs.some(p => p.tagName !== 'P')) throw new Error('即刻正文结构变化，无法验证段落');
        const text = node => node.nodeType === Node.TEXT_NODE ? node.textContent : node.nodeName === 'BR' ? '\\n' : [...node.childNodes].map(text).join('');
        const body = paragraphs.map(p => p.childNodes.length === 1 && p.firstChild.nodeName === 'BR' ? '' : text(p)).join('\\n');
        const visible = el => el.getBoundingClientRect().width > 0 && el.getBoundingClientRect().height > 0 && getComputedStyle(el).visibility !== 'hidden';
        const tiles = [...root.querySelectorAll('[aria-roledescription="sortable"]')];
        const images = await Promise.all(tiles.map(async tile => {
          const img = tile.querySelector('img');
          let digest = '';
          if (img?.complete && img.naturalWidth > 0) {
            // Hash decoded pixels: Jike revokes/recreates blob URLs during upload.
            // This detached canvas reads the preview without fetching a stale URL.
            const canvas = new OffscreenCanvas(img.naturalWidth, img.naturalHeight);
            const context = canvas.getContext('2d');
            context.drawImage(img, 0, 0);
            const pixels = context.getImageData(0, 0, canvas.width, canvas.height).data;
            digest = canvas.width + 'x' + canvas.height + ':' + [...new Uint8Array(await crypto.subtle.digest('SHA-256', pixels))].map(b => b.toString(16).padStart(2,'0')).join('');
          }
          return {identity:tile.id + ':' + (digest || img?.getAttribute('src') || ''), ready:!!img && img.complete && img.naturalWidth > 0 &&
            !tile.querySelector('[class*="_loading_"], [role="progressbar"], .mantine-Loader-root')};
        }));
        if (root.querySelectorAll('img').length !== images.length) throw new Error('即刻附件结构变化，无法核对');
        return {body,images,accepted:root.querySelector('button[type="submit"]')?.disabled === false,
          rejected:[...root.querySelectorAll('[role="alert"]')].some(el => visible(el) && el.textContent.trim().length > 0)};
        """
}
