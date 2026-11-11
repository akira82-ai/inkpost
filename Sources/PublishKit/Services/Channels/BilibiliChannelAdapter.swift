import Foundation

/// Ordinary dynamics only. Click and paste into the website; never invoke Publish.
final class BilibiliChannelAdapter: ChannelAdapter {
    let platform: PlatformID = .bilibili
    let capabilities = ChannelCapabilities(usesTitle: true, maximumImages: .max,
        entryURL: "https://t.bilibili.com/", maximumTitleCharacters: 20)
    private static let editor = ".bili-dyn-publishing .bili-rich-textarea__inner[contenteditable=\"true\"]"
    private static let title = ".bili-dyn-publishing__title__input"
    private var opened = false
    private var clearingAttempted = false
    private var cleared = false
    private var titleAttempted = false
    private var bodyAttempted = false
    private var confirmed: [String] = []
    private var pendingImage = false

    func validate(_ request: ChannelRequest) throws {
        guard !request.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChannelFailure(code: .contentUnsupported, stage: .validatingRequest,
                detail: "B站动态正文必填", recovery: .contentChangeRequired)
        }
        guard request.title.utf16.count <= 20 else {
            throw ChannelFailure(code: .contentUnsupported, stage: .validatingRequest,
                detail: "B站动态标题超过网页 20 字符限制（emoji 可能占多个字符），不会截断", recovery: .contentChangeRequired)
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
        context.diagnostic("打开 B站动态页；点击标题和正文后原样粘贴，不点击发布")
        let raw = try await context.bridge.run("""
            // bilibili:open-editor
            const valid = value => { const url = new URL(value); return url.origin === 'https://t.bilibili.com' && url.pathname === '/'; };
            if (!valid(await page.url())) {
              if (\(opened ? "true" : "false")) throw new Error('B站已离开原动态页，请返回原页面后继续');
              await page.goto('https://t.bilibili.com/');
            }
            await page.waitForFunction(() => !!document.querySelector('\(Self.editor)') ||
              [...document.querySelectorAll('a,button,.header-login-entry')].some(el => el.getBoundingClientRect().width > 0 && /^(登录|立即登录)$/.test(el.textContent.trim())), undefined, {timeout:20000});
            const loginRequired = await page.evaluate(() => [...document.querySelectorAll('a,button,.header-login-entry')].some(el =>
              el.getBoundingClientRect().width > 0 && /^(登录|立即登录)$/.test(el.textContent.trim())));
            cliLog(JSON.stringify({ok:true,loginRequired}));
            """)
        struct Opening: Decodable { let loginRequired: Bool }
        try context.advance(.checkingLogin)
        if try JSONDecoder().decode(Opening.self, from: Data(raw.utf8)).loginRequired {
            return .waitingForUser(.init(code: .loginRequired, stage: .checkingLogin,
                detail: "请登录 B站后在原动态页继续", recovery: .loginRequired))
        }
        opened = true
        try context.advance(.fillingContent)
        let initial: State
        if !cleared {
            guard !clearingAttempted else { throw failure("B站上次清空结果未知，请检查原页面") }
            clearingAttempted = true
            _ = try await context.bridge.run("""
                // bilibili:clear-draft
                const url = new URL(await page.url());
                if (url.origin !== 'https://t.bilibili.com' || url.pathname !== '/') throw new Error('B站已离开动态首页');
                const count = await page.evaluate(() => document.querySelectorAll('.bili-dyn-publishing .bili-pics-uploader__item').length);
                for (let i = 0; i < count; i++) {
                  await page.hover('.bili-dyn-publishing .bili-pics-uploader__item >> nth=0', {label:'显示旧图片移除入口'});
                  await page.click('.bili-dyn-publishing .bili-pics-uploader__item__remove >> nth=0', {label:'移除 B站旧图片'});
                  await page.waitForFunction(expected => document.querySelectorAll('.bili-dyn-publishing .bili-pics-uploader__item').length === expected, count - i - 1, {timeout:5000});
                }
                await page.click('\(Self.title)', {label:'清空 B站旧标题'});
                await page.press('\(Self.title)', 'Meta+A');
                await page.keyboard.press('Backspace');
                await page.click('\(Self.editor)', {label:'清空 B站旧正文'});
                await page.press('\(Self.editor)', 'Meta+A');
                await page.keyboard.press('Backspace');
                cliLog(JSON.stringify({ok:true}));
                """)
            initial = try await read(context.bridge)
            guard initial.title.isEmpty, initial.body.isEmpty, initial.images.isEmpty else {
                throw failure("B站旧标题、正文或图片未清空，已停止填写")
            }
            cleared = true
        } else {
            initial = try await read(context.bridge)
        }
        try check(initial, request: request, allowEmpty: true)
        try validateImages(initial.images)
        if initial.title.isEmpty && !request.title.isEmpty {
            guard !titleAttempted else { throw failure("B站标题上次填写结果未知，不会重复粘贴") }
            titleAttempted = true
            _ = try await ClipboardPasteService.withTextPaste(request.title) {
                try await context.bridge.run("""
                    // bilibili:paste-title
                    await page.click('\(Self.title)', {label:'填写 B站动态标题'});
                    await page.keyboard.press('Meta+V');
                    cliLog(JSON.stringify({ok:true}));
                    """)
            }
        }
        if initial.body.isEmpty {
            guard !bodyAttempted else { throw failure("B站正文上次填写结果未知，不会重复粘贴") }
            bodyAttempted = true
            _ = try await ClipboardPasteService.withTextPaste(request.body) {
                try await context.bridge.run("""
                    // bilibili:paste-body
                    await page.click('\(Self.editor)', {label:'填写 B站动态正文'});
                    await page.keyboard.press('Meta+V');
                    cliLog(JSON.stringify({ok:true}));
                    """)
            }
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
                    // bilibili:add-image
                    const expanded = await page.evaluate(() => !!document.querySelector('.bili-pics-uploader__add')?.getBoundingClientRect().width);
                    const chooserPromise = page.waitForFileChooser({timeout:10000});
                    await page.click(expanded ? '.bili-pics-uploader__add' : '.bili-dyn-publishing__tools__item.pic', {label:'添加 B站下一张图片'});
                    const chooser = await chooserPromise;
                    await chooser.setFiles(\(context.bridge.jsStr(paths[index])));
                    cliLog(JSON.stringify({ok:true}));
                    """)
            }
            do {
                _ = try await context.bridge.run("""
                    // bilibili:wait-images
                    await page.waitForFunction(expected => {
                      const tiles = [...document.querySelectorAll('.bili-dyn-publishing .bili-pics-uploader__item')];
                      return tiles.some(tile => tile.querySelector('[msg]')?.getAttribute('msg')) ||
                        (tiles.length === expected && tiles.every(tile => tile.classList.contains('success')));
                    }, \(index + 1), {timeout:60000});
                    cliLog(JSON.stringify({ok:true}));
                    """)
            } catch {
                if error is CancellationError || Task.isCancelled { throw CancellationError() }
                throw ChannelFailure(code: .uploadFailed, stage: .uploadingAssets,
                    detail: "B站第 \(index + 1) 张图片未确认完成：\(error.localizedDescription)", recovery: .inspectionRequired)
            }
            let added = try await read(context.bridge)
            try check(added, request: request)
            try validateImages(added.images)
            guard added.images.count == index + 1, added.images.allSatisfy(\.ready) else {
                throw failure("B站图片未确认完整就绪，不会重复添加")
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
            throw failure("B站图片数量、顺序或就绪状态不完整")
        }
        guard final.accepted else {
            return .waitingForUser(.init(code: .editorUnavailable, stage: .verifyingContent,
                detail: "B站未允许发布，请到原页面检查字数、登录或页面提示", recovery: .inspectionRequired))
        }
        return .readyForReview(message: "B站标题、正文及 \(request.assets.count) 张图片已核对，请手工发布")
    }

    struct Image: Decodable { let identity: String; let ready: Bool }
    struct State: Decodable { let title: String; let body: String; let images: [Image]; let accepted: Bool; let rejected: Bool }

    func check(_ state: State, request: ChannelRequest, allowEmpty: Bool = false) throws {
        guard !state.rejected else {
            throw ChannelFailure(code: .contentUnsupported, stage: .verifyingContent,
                detail: "B站图片或编辑器报告错误，请检查原页面", recovery: .contentChangeRequired)
        }
        func lines(_ text: String) -> String { text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n") }
        guard state.title == request.title || (allowEmpty && state.title.isEmpty),
              lines(state.body) == lines(request.body) || (allowEmpty && state.body.isEmpty) else {
            throw failure("B站标题或正文与原稿不一致（平台可能处理首尾空白），请检查原页面；不会覆盖或重复粘贴")
        }
    }

    func validateImages(_ images: [Image]) throws {
        guard images.count >= confirmed.count,
              Array(images.prefix(confirmed.count).map(\.identity)) == confirmed,
              images.prefix(confirmed.count).allSatisfy(\.ready),
              images.count == confirmed.count + (pendingImage ? 1 : 0) else {
            throw failure("B站附件已变化或上次添加结果未知，保留现场，不会重复添加")
        }
    }

    private func failure(_ detail: String) -> ChannelFailure {
        .init(code: .verificationFailed, stage: .verifyingContent, detail: detail, recovery: .inspectionRequired)
    }

    private func read(_ bridge: EgoBridge) async throws -> State {
        struct Result: Decodable { let value: State }
        let raw = try await bridge.run("""
            // bilibili:read-page
            const value = await page.evaluate(async () => { \(Self.readSource) });
            cliLog(JSON.stringify({ok:true,value}));
            """)
        return try JSONDecoder().decode(Result.self, from: Data(raw.utf8)).value
    }

    static let readSource = """
        if (location.origin !== 'https://t.bilibili.com' || location.pathname !== '/') throw new Error('B站已离开动态首页');
        const editors = [...document.querySelectorAll('\(editor)')];
        if (editors.length !== 1) throw new Error('B站正文编辑器缺失或不唯一');
        const editor = editors[0], root = editor.closest('.bili-dyn-publishing');
        if (!editor.getBoundingClientRect().width || !root) throw new Error('B站正文不可操作');
        const titles = [...root.querySelectorAll('\(title)')];
        if (titles.length !== 1 || !titles[0].getBoundingClientRect().width || titles[0].maxLength !== 20) throw new Error('B站标题控件结构变化');
        if ([...editor.childNodes].some(node => node.nodeType !== Node.TEXT_NODE)) throw new Error('B站正文含未知富文本结构，无法完整核对');
        // Observed caret scaffolding, not user content. Never trim the actual body.
        const raw = editor.textContent;
        let body;
        if (editor.classList.contains('empty') && raw === '\\u200b\\n') body = '';
        else {
          if (!raw.startsWith('\\u200b') || !raw.endsWith(' \\n')) throw new Error('B站正文占位结构变化，无法核对');
          body = raw.slice(1, -2);
        }
        const tiles = [...root.querySelectorAll('.bili-pics-uploader__item')];
        const images = await Promise.all(tiles.map(async tile => {
          const preview = tile.querySelector('.bili-pics-uploader-item-preview__pic');
          const style = preview?.style.backgroundImage || '';
          const match = style.match(/^url\\(["']?(data:image\\/[^"')]+)["']?\\)$/);
          let identity = '', decoded = false;
          if (match) {
            const img = new Image(); img.src = match[1];
            await img.decode(); decoded = img.naturalWidth > 0 && img.naturalHeight > 0;
            identity = img.naturalWidth + 'x' + img.naturalHeight + ':' + [...new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(match[1])))].map(b => b.toString(16).padStart(2,'0')).join('');
          }
          return {identity,ready:decoded && tile.classList.contains('success') && !tile.querySelector('[msg]')?.getAttribute('msg')};
        }));
        const buttons = [...root.querySelectorAll('.bili-dyn-publishing__action.launcher')];
        if (buttons.length !== 1 || buttons[0].textContent.trim() !== '发布') throw new Error('B站发布控件结构变化');
        const visible = el => el.getBoundingClientRect().width > 0 && getComputedStyle(el).visibility !== 'hidden';
        return {title:titles[0].value,body,images,accepted:visible(buttons[0]) && !buttons[0].classList.contains('disabled') && buttons[0].getAttribute('aria-disabled') !== 'true',
          rejected:tiles.some(tile => !!tile.querySelector('[msg]')?.getAttribute('msg')) || [...root.querySelectorAll('[role="alert"]')].some(el => visible(el) && el.textContent.trim())};
        """
}
