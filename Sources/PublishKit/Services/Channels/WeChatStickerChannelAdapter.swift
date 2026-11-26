import Foundation

final class WeChatStickerChannelAdapter: ChannelAdapter {
    let platform: PlatformID = .wechatSticker
    let capabilities = ChannelCapabilities(usesTitle: true, maximumImages: .max,
        entryURL: "https://mp.weixin.qq.com/", maximumTitleCharacters: 20, maximumBodyCharacters: 1000)

    private static let title = ".title-editor__input .ProseMirror"
    private static let body = ".js_pmEditorArea .ProseMirror"
    private static let editorIdentity = """
    location.origin === 'https://mp.weixin.qq.com' &&
    location.pathname === '/cgi-bin/appmsg' &&
    new URLSearchParams(location.search).get('type') === '77'
    """
    private var openingAttempted = false
    private var writingStarted = false
    private var textPasteDispatched = false

    @MainActor
    func execute(request: ChannelRequest, context: ChannelExecutionContext) async throws -> ChannelOutcome {
        try context.advance(.validatingRequest)
        guard !request.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              request.title.count <= 20, request.body.count <= 1000 else {
            throw ChannelFailure(code: .contentUnsupported, stage: .validatingRequest,
                detail: "微信公众号贴图标题选填（最多 20 字），正文必填（最多 1000 字）",
                recovery: .contentChangeRequired)
        }
        let paths = try context.uploadPaths(for: request)
        try context.advance(.openingEditor)
        if !openingAttempted {
            let page = try context.bridge
            let raw = try await page.run("""
                if (new URL(await page.url()).origin !== 'https://mp.weixin.qq.com') {
                    await page.goto('https://mp.weixin.qq.com/');
                }
                await page.waitForFunction(() =>
                    [...document.querySelectorAll('.new-creation__menu-title')].some(e => e.getClientRects().length && e.textContent.trim() === '贴图') ||
                    !!document.querySelector('.login__type__container, .login__type__container__scan, .login__qrcode'), undefined, {timeout:20000});
                const login = await page.evaluate(() =>
                    ![...document.querySelectorAll('.new-creation__menu-title')].some(e => e.getClientRects().length && e.textContent.trim() === '贴图'));
                cliLog(JSON.stringify({login}));
                """)
            struct Home: Decodable { let login: Bool }
            if try JSONDecoder().decode(Home.self, from: Data(raw.utf8)).login {
                try context.advance(.checkingLogin)
                return .waitingForUser(.init(code: .loginRequired, stage: .checkingLogin,
                    detail: "请登录微信公众号后台后继续", recovery: .loginRequired))
            }
            openingAttempted = true
            do {
                let raw = try await page.run("""
                    const popup = page.waitForEvent('popup', {timeout:10000}).then(value => value, () => null);
                    await channelClick('.new-creation__menu-title:text-is("贴图")', {label:'打开公众号贴图创作'});
                    const editor = await popup;
                    if (!editor) throw new Error('没有收到贴图编辑页');
                    cliLog(JSON.stringify({label:editor.label}));
                    """)
                struct Popup: Decodable { let label: String }
                try context.followBrowserPage(JSONDecoder().decode(Popup.self, from: Data(raw.utf8)).label)
            } catch is CancellationError { throw CancellationError() }
            catch {
                throw inspection(.openingEditor, "无法确认新打开的贴图页，请检查浏览器后继续")
            }
        }

        let page = try context.bridge
        _ = try await page.run("""
            await page.waitForFunction(() => (\(Self.editorIdentity)) &&
              ['\(Self.title)', '\(Self.body)', '.image-selector'].every(s => {
                  const nodes = [...document.querySelectorAll(s)].filter(e => e.getClientRects().length);
                  return nodes.length === 1;
              }), undefined, {timeout:20000});
            cliLog(JSON.stringify({ok:true}));
            """)
        let initial = try await read(page)
        if writingStarted {
            // A previous write may have finished after the browser command returned.
            // Recheck the editor, but never replay a write with an uncertain result.
            guard textPasteDispatched else {
                throw inspection(.fillingContent, "上次粘贴结果待确认，请检查贴图文字")
            }
            return try verify(initial, request: request, context: context)
        }
        guard initial.title.isEmpty, initial.body.isEmpty, initial.images == 0 else {
            throw inspection(.fillingContent, "贴图编辑器已有内容，请检查原草稿")
        }
        guard !initial.warning else { throw inspection(.fillingContent, "公众号提示需要人工检查") }

        try context.advance(.fillingContent)
        writingStarted = true
        if !request.title.isEmpty { try await paste(request.title, into: Self.title, using: page) }
        try await paste(request.body, into: Self.body, using: page)
        textPasteDispatched = true
        let filled = try await read(page)
        guard filled.images == 0, !filled.warning else {
            throw inspection(.fillingContent, "贴图附件状态变化或页面出现提示，请检查编辑器")
        }

        if !paths.isEmpty {
            try context.advance(.uploadingAssets)
            _ = try await page.run("""
                if (!await page.evaluate(() => \(Self.editorIdentity))) throw new Error('贴图编辑页已变化');
                await page.hover('.image-selector__add', {label:'显示贴图上传菜单'});
                await page.waitForFunction(() => {
                    const labels = [...document.querySelectorAll('.image-selector__add .js_upload_btn_container label')];
                    return labels.filter(label => {
                        const rect = label.getBoundingClientRect();
                        const hit = document.elementFromPoint(rect.x + rect.width / 2, rect.y + rect.height / 2);
                        return rect.width > 0 && rect.height > 0 && (hit === label || label.contains(hit));
                    }).length === 1;
                }, undefined, {timeout:5000}).catch(() => { throw new Error('悬停后未出现可点击的「本地上传」菜单'); });
                const chooser = page.waitForFileChooser({timeout:10000}).then(value => value, () => null);
                await channelClick('.image-selector__add .js_upload_btn_container label', {label:'打开本地选图'});
                const selection = await chooser;
                if (!selection) throw new Error('未收到本地选图事件');
                await selection.setFiles(\(page.jsArr(paths)));
                await page.waitForFunction(expected => {
                    \(Self.imageReadSource)
                    return tiles.length === expected && ready === expected;
                }, \(paths.count), {timeout:30000});
                cliLog(JSON.stringify({ok:true}));
                """)
            try context.progress(completed: paths.count, total: paths.count)
        }
        return try verify(try await read(page), request: request, context: context)
    }

    private struct EditorState: Decodable {
        let title: String
        let body: String
        let images: Int
        let ready: Int
        let warning: Bool
    }

    private static let imageReadSource = """
    const tiles = [...document.querySelectorAll('.image-selector__bottom-list-item')].filter(e => e.getClientRects().length);
    const ready = tiles.filter(tile => [tile, ...tile.children].some(e => getComputedStyle(e).backgroundImage.startsWith('url('))).length;
    """

    private func read(_ page: EgoBridge) async throws -> EditorState {
        let raw = try await page.run("""
            const state = await page.evaluate(() => {
                if (!(\(Self.editorIdentity))) throw new Error('当前页面不是公众号贴图编辑器');
                const field = selector => {
                    const nodes = [...document.querySelectorAll(selector)].filter(e => e.getClientRects().length);
                    if (nodes.length !== 1) throw new Error('无法唯一定位贴图文字框');
                    const editor = nodes[0];
                    const readText = node => {
                        if (node.nodeType === Node.TEXT_NODE) return node.textContent;
                        if (node.nodeType === Node.ELEMENT_NODE && node.matches('.editor_placeholder.ProseMirror-widget')) return '';
                        if (node.nodeName === 'BR') return node.classList.contains('ProseMirror-trailingBreak') ? '' : '\\n';
                        return [...node.childNodes].map(readText).join('');
                    };
                    const blocks = [...editor.children];
                    if (blocks.length && blocks.every(e => e.tagName === 'P') && editor.childNodes.length === blocks.length) {
                        return blocks.map(readText).join('\\n');
                    }
                    return readText(editor);
                };
                \(Self.imageReadSource)
                const warning = [...document.querySelectorAll('[role="alert"], .weui-desktop-toast, .weui-desktop-dialog')]
                    .some(e => e.getClientRects().length && /失败|异常|风险|验证码|超出|上限/.test(e.innerText));
                return {title:field('\(Self.title)'), body:field('\(Self.body)'), images:tiles.length, ready, warning};
            });
            cliLog(JSON.stringify(state));
            """)
        return try JSONDecoder().decode(EditorState.self, from: Data(raw.utf8))
    }

    @MainActor
    private func paste(_ text: String, into selector: String, using page: EgoBridge) async throws {
        _ = try await ClipboardPasteService.withTextPaste(text) {
            try await page.run("""
                if (!await page.evaluate(() => \(Self.editorIdentity))) throw new Error('贴图编辑页已变化');
                await channelClick('\(selector)', {label:'聚焦贴图输入框'});
                await waitForEditorFocus('\(selector)');
                await page.keyboard.press('Meta+V');
                cliLog(JSON.stringify({ok:true}));
                """)
        }
    }

    @MainActor
    private func verify(_ state: EditorState, request: ChannelRequest, context: ChannelExecutionContext) throws -> ChannelOutcome {
        try context.advance(.verifyingContent)
        guard state.images == request.assets.count,
              state.ready == state.images, !state.warning else {
            throw inspection(.verifyingContent, "无法确认贴图图片状态，请在公众号页面检查")
        }
        return .readyForReview(message: "请检查微信公众号贴图的标题、正文和图片，再手工发表")
    }

    private func inspection(_ stage: ChannelStage, _ detail: String) -> ChannelFailure {
        .init(code: .verificationFailed, stage: stage, detail: detail, recovery: .inspectionRequired)
    }
}
