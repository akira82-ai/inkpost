import Foundation

/// Ordinary pins only. The website uploads attachments only after the user's final Publish action.
final class JuejinChannelAdapter: ChannelAdapter {
    let platform: PlatformID = .juejin
    let capabilities = ChannelCapabilities(usesTitle: true, maximumImages: .max,
        entryURL: "https://juejin.cn/pins", maximumBodyCharacters: 1000)
    private static let editor = ".pin-editor .rich-editor[contenteditable=\"true\"]"
    private var opened = false
    private var bodyAttempted = false
    private var confirmed: [String] = []
    private var pendingImage = false

    func expectedBody(for request: ChannelRequest) -> String {
        (request.title.isEmpty ? "" : request.title + "\n") + request.body
    }

    func validate(_ request: ChannelRequest) throws {
        guard !request.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChannelFailure(code: .contentUnsupported, stage: .validatingRequest,
                detail: "掘金沸点正文必填", recovery: .contentChangeRequired)
        }
        // The observed web composer and its submit validation count JavaScript UTF-16 units.
        guard expectedBody(for: request).utf16.count <= 1000 else {
            throw ChannelFailure(code: .contentUnsupported, stage: .validatingRequest,
                detail: "掘金沸点标题与正文合计超过网页 1000 字符限制（emoji 可能占多个字符），不会截断", recovery: .contentChangeRequired)
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
        let paths = try context.uploadPaths(for: request)
        try context.advance(.openingEditor)
        context.diagnostic("打开掘金沸点；首次填写清空旧正文和附件，恢复时保留现场")
        let raw = try await context.bridge.run("""
            // juejin:open-editor
            const current = await page.url();
            const valid = value => { const url = new URL(value); return url.origin === "https://juejin.cn" && ["/pins", "/pins/", "/pins/new", "/pins/hot", "/pins/following"].includes(url.pathname); };
            if (!valid(current)) {
              if (\(opened ? "true" : "false")) throw new Error('掘金已离开原沸点页，请返回原页面后继续');
              await page.goto('https://juejin.cn/pins');
            }
            await page.waitForFunction(() => !!document.querySelector('\(Self.editor)') ||
              [...document.querySelectorAll('button,a')].some(el => el.getBoundingClientRect().width > 0 && /^(登录|登录\\s*\\/\\s*注册|立即登录)$/.test(el.textContent.trim())), undefined, {timeout:20000});
            const loginRequired = await page.evaluate(() =>
              !document.querySelector('a[href="https://juejin.cn/notification"], a[href="/notification"]') &&
              [...document.querySelectorAll('button,a')].some(el => el.getBoundingClientRect().width > 0 && /^(登录|登录\\s*\\/\\s*注册|立即登录)$/.test(el.textContent.trim())));
            cliLog(JSON.stringify({ok:true,loginRequired}));
            """)
        struct Opening: Decodable { let loginRequired: Bool }
        try context.advance(.checkingLogin)
        if try JSONDecoder().decode(Opening.self, from: Data(raw.utf8)).loginRequired {
            return .waitingForUser(.init(code: .loginRequired, stage: .checkingLogin,
                detail: "请登录掘金后在原页面继续此渠道", recovery: .loginRequired))
        }
        opened = true
        try context.advance(.fillingContent)
        let initial = try await read(context.bridge)
        if !bodyAttempted {
            // Mark before any clearing or text insertion. An uncertain write is never replayed on resume.
            bodyAttempted = true
            _ = try await context.bridge.run("""
                // juejin:replace-body
                for (let i = 0; i < \(initial.images.count); i++) {
                  await page.click('.pin-editor .preview-image .delete >> nth=0', {label:'移除沸点原有附件'});
                }
                for (let i = 0; i < \(initial.linkCount); i++) {
                  await page.click('.pin-editor .preview-link .close', {label:'移除沸点原有链接卡片'});
                }
                await page.click('\(Self.editor)', {label:'替换沸点原有正文'});
                await page.keyboard.press('Meta+A');
                await page.keyboard.insertText(\(context.bridge.jsStr(expectedBody(for: request))));
                cliLog(JSON.stringify({ok:true}));
                """)
        }
        try check(try await read(context.bridge), request: request)
        try context.advance(.uploadingAssets)
        for index in request.assets.indices {
            try Task.checkCancellation()
            let state = try await read(context.bridge)
            try check(state, request: request)
            try validateImages(state.images)
            if index < confirmed.count { continue }
            if !pendingImage {
                pendingImage = true
                try context.progress(completed: index, total: request.assets.count)
                _ = try await context.bridge.run("""
                    // juejin:add-image
                    await page.setInputFiles('.pin-editor input#photo[type=file]', \(context.bridge.jsStr(paths[index])));
                    cliLog(JSON.stringify({ok:true}));
                    """)
            }
            _ = try await context.bridge.run("""
                // juejin:wait-images
                await page.waitForFunction(async expected => {
                  const state = await (async () => { \(Self.readSource) })();
                  return state.images.length === expected && state.images.every(image => image.ready);
                }, \(index + 1), {timeout:30000});
                cliLog(JSON.stringify({ok:true}));
                """)
            let added = try await read(context.bridge)
            try check(added, request: request)
            try validateImages(added.images)
            guard added.images.count == index + 1, added.images.allSatisfy(\.ready) else {
                throw failure("掘金第 \(index + 1) 张附件未确认，需检查页面")
            }
            confirmed = added.images.map(\.identity)
            pendingImage = false
            try context.progress(completed: index + 1, total: request.assets.count)
        }
        try context.advance(.verifyingContent)
        let final = try await read(context.bridge)
        try check(final, request: request)
        try validateImages(final.images)
        guard !pendingImage, final.images.count == request.assets.count, final.images.allSatisfy(\.ready) else {
            throw failure("掘金附件数量或状态与任务不一致")
        }
        guard final.accepted else {
            return .waitingForUser(.init(code: .editorUnavailable, stage: .verifyingContent,
                detail: "掘金未允许发布，请检查登录、绑定手机号或页面提示后继续", recovery: .inspectionRequired))
        }
        return .readyForReview(message: "掘金正文及 \(request.assets.count) 张附件已填好；平台将在你点击发布时上传图片")
    }

    struct Image: Decodable { let identity: String; let ready: Bool }
    struct State: Decodable { let body: String; let images: [Image]; let accepted: Bool; let rejected: Bool; let linkCount: Int }

    func check(_ state: State, request: ChannelRequest) throws {
        guard state.linkCount == 0 else { throw failure("掘金已有任务以外的链接卡片，已保留现场，请移除后继续") }
        guard !state.rejected else {
            throw ChannelFailure(code: .contentUnsupported, stage: .verifyingContent,
                detail: "掘金编辑器报告错误，请检查页面提示", recovery: .contentChangeRequired)
        }
        func lines(_ value: String) -> String {
            value.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        }
        guard lines(state.body) == lines(expectedBody(for: request)) else {
            throw failure("掘金正文与任务不一致，已保留现场；不会再次清空或覆盖")
        }
    }

    func validateImages(_ images: [Image]) throws {
        guard images.count >= confirmed.count,
              Array(images.prefix(confirmed.count).map(\.identity)) == confirmed,
              images.prefix(confirmed.count).allSatisfy(\.ready),
              images.count == confirmed.count + (pendingImage ? 1 : 0) else {
            throw failure("掘金附件已变化或上次添加结果未知，不会重复添加")
        }
    }

    private func failure(_ detail: String) -> ChannelFailure {
        .init(code: .verificationFailed, stage: .verifyingContent, detail: detail, recovery: .inspectionRequired)
    }

    @MainActor
    private func read(_ bridge: EgoBridge) async throws -> State {
        struct Result: Decodable { let value: State }
        let raw = try await bridge.run("""
            // juejin:read-page
            const value = await page.evaluate(async () => { \(Self.readSource) });
            cliLog(JSON.stringify({ok:true,value}));
            """)
        return try JSONDecoder().decode(Result.self, from: Data(raw.utf8)).value
    }

    static let readSource = """
        if (location.origin !== 'https://juejin.cn' || !/^\\/pins(?:\\/(?:new|hot|following))?\\/?$/.test(location.pathname)) throw new Error('掘金已离开沸点页');
        const editors = [...document.querySelectorAll('\(editor)')];
        if (editors.length !== 1) throw new Error('掘金编辑器缺失或不唯一');
        const editor = editors[0], root = editor.closest('.pin-editor');
        if (!editor.getBoundingClientRect().width || !root) throw new Error('掘金编辑器不可操作');
        const text = node => {
          if (node.nodeType === Node.TEXT_NODE) return node.textContent;
          if (node.nodeName === 'BR') return '\\n';
          if (!['DIV','P','SPAN','A'].includes(node.nodeName)) throw new Error('掘金正文结构变化，无法完整验证');
          const children = [...node.childNodes].filter(child => child.nodeType !== Node.TEXT_NODE || child.textContent !== '');
          if (children.length === 1 && children[0].nodeName === 'BR') return '';
          return children.map((child, index) =>
            (index > 0 && ['DIV','P'].includes(child.nodeName) ? '\\n' : '') + text(child)).join('');
        };
        const nodes = [...editor.childNodes].filter(node => node.nodeType !== Node.TEXT_NODE || node.textContent !== '');
        if (nodes.at(-1)?.nodeName === 'BR') nodes.pop();
        const body = nodes.map((node, index) =>
          (index > 0 && ['DIV','P'].includes(node.nodeName) ? '\\n' : '') + text(node)).join('');
        const tiles = [...root.querySelectorAll('.preview-image')];
        const images = await Promise.all(tiles.map(async (tile, index) => {
          const img = tile.querySelector('img');
          const ready = !!img && img.complete && img.naturalWidth > 0;
          let digest = '';
          if (ready) {
            const canvas = new OffscreenCanvas(img.naturalWidth, img.naturalHeight);
            const context = canvas.getContext('2d');
            context.drawImage(img, 0, 0);
            const pixels = context.getImageData(0, 0, canvas.width, canvas.height).data;
            digest = [...new Uint8Array(await crypto.subtle.digest('SHA-256', pixels))].map(b => b.toString(16).padStart(2,'0')).join('');
          }
          if (tile.getAttribute('index') !== String(index)) throw new Error('掘金附件顺序结构变化');
          return {identity:(img?.getAttribute('src') || '') + ':' + img?.naturalWidth + 'x' + img?.naturalHeight + ':' + digest, ready};
        }));
        const buttons = [...root.querySelectorAll('button')].filter(button => button.textContent.trim() === '发布');
        if (buttons.length !== 1 || root.querySelectorAll('.word-counter').length !== 1) throw new Error('掘金发布控件结构变化');
        const counter = root.querySelector('.word-counter').textContent.match(/^\\s*(\\d+)\\s*\\/\\s*(\\d+)\\s*$/);
        if (!counter) throw new Error('掘金字数计数结构变化');
        const withinLimit = Number(counter[1]) <= Number(counter[2]);
        const visible = el => el.getBoundingClientRect().width > 0 && getComputedStyle(el).visibility !== 'hidden';
        return {body, images, linkCount:root.querySelectorAll('.preview-link').length, accepted:!buttons[0].disabled && buttons[0].classList.contains('active') && withinLimit,
          rejected:[...root.querySelectorAll('[role="alert"]')].some(el => visible(el) && el.textContent.trim().length > 0)};
        """
}
