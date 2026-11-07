import Foundation

/// A task-scoped thoughts workflow. Browser writes use ego Lite's native interactions only.
final class ZhihuChannelAdapter: ChannelAdapter {
    let platform: PlatformID = .zhihu
    let capabilities = ChannelCapabilities(usesTitle: true, maximumImages: 6, entryURL: "https://www.zhihu.com/", requiresTitle: false, maximumTitleCharacters: 44, maximumBodyCharacters: 1899)
    private static let titleTarget = "textarea[name=\"title\"]"
    private static let bodyTarget = "[contenteditable=\"true\"]"
    private var images = ImageProgress()

    @MainActor
    func execute(request: ChannelRequest, context: ChannelExecutionContext) async throws -> ChannelOutcome {
        try context.advance(.validatingRequest)
        try PlatformRules.validate(request, capabilities: capabilities)
        let uploadPaths = try context.uploadPaths(for: request)
        try context.advance(.openingEditor)
        context.diagnostic("打开知乎首页，定位「分享此刻的想法」")
        let raw = try await Self.navigate(bridge: context.bridge, url: capabilities.entryURL!)
        let navigation = try JSONDecoder().decode(Navigation.self, from: Data(raw.utf8))
        try context.advance(.checkingLogin)
        if navigation.loginRequired == true {
            return .waitingForUser(.init(code: .loginRequired, stage: .checkingLogin,
                detail: "请登录知乎后继续此渠道", recovery: .loginRequired))
        }
        guard navigation.composerReady == true else { throw failure(.editorUnavailable, .openingEditor, "知乎想法编辑器尚未展开") }
        context.diagnostic("想法编辑器已展开")

        // Inspect all existing content before the first write; preserve conflicting user content.
        let initial = try await readPage(context.bridge)
        try initial.checkContent(request, allowEmpty: true)
        try images.validate(initial.images)
        try context.advance(.fillingContent)
        try await fillTitle(request.title, existing: initial.title, bridge: context.bridge)
        try await fillBody(request.taggedBody, existing: initial.body, bridge: context.bridge)
        let filled = try await readPage(context.bridge)
        try filled.checkContent(request, allowEmpty: false)
        context.diagnostic("标题、完整正文与标签已回读核对")

        try context.advance(.uploadingAssets)
        try await uploadImages(uploadPaths, context: context)
        try context.advance(.verifyingContent)
        let final = try await readPage(context.bridge)
        try final.checkContent(request, allowEmpty: false)
        try images.validate(final.images)
        guard final.images.count == request.assets.count, final.images.allSatisfy(\.ready), images.pending == nil else {
            throw failure(.verificationFailed, .verifyingContent, "图片数量或上传状态不完整")
        }
        return .readyForReview(message: "标题、正文、标签及 \(request.assets.count) 张图片已核对，请检查后亲手发想法")
    }

    private func fillTitle(_ title: String, existing: String, bridge: EgoBridge) async throws {
        guard !title.isEmpty, existing.isEmpty else { return }
        _ = try await bridge.fill(target: Self.titleTarget, text: title)
    }

    private func fillBody(_ body: String, existing: String, bridge: EgoBridge) async throws {
        guard existing.isEmpty else { return }
        _ = try await ClipboardPasteService.withTextPaste {
            try await bridge.run("""
                // zhihu:paste-body
                await page.click(\(bridge.jsStr(Self.bodyTarget)), {label:'粘贴完整正文和标签'});
                await page.keyboard.paste(\(bridge.jsStr(body)));
                cliLog(JSON.stringify({ok:true}));
                """)
        }
    }

    @MainActor
    private func uploadImages(_ paths: [String], context: ChannelExecutionContext) async throws {
        guard !paths.isEmpty else { return }
        let clipboard = try ImageClipboardSession.acquire()
        defer { clipboard.restore() }
        for index in paths.indices {
            try Task.checkCancellation()
            let current = try await readPage(context.bridge)
            try images.validate(current.images)
            if index < images.confirmed.count { continue }
            if images.pending == nil {
                guard current.images.count == index else { throw failure(.verificationFailed, .uploadingAssets, "知乎附件与任务不一致，未继续粘贴") }
                try clipboard.writePNG(path: paths[index])
                // Record uncertainty before dispatch: a failed command may already have pasted.
                images.pending = index
                try context.progress(completed: index, total: paths.count)
                _ = try await context.bridge.run("""
                    // zhihu:paste-image
                    await page.click(\(context.bridge.jsStr(Self.bodyTarget)), {label:'粘贴下一张想法图片'});
                    await page.keyboard.press('Meta+V');
                    cliLog(JSON.stringify({ok:true}));
                    """)
            }
            try await waitForImages(context.bridge, count: index + 1)
            let completed = try await readPage(context.bridge)
            try images.validate(completed.images)
            guard completed.images.count == index + 1, completed.images.allSatisfy(\.ready) else {
                throw failure(.uploadFailed, .uploadingAssets, "第 \(index + 1) 张图片尚未上传完成")
            }
            images.confirmed = completed.images.map(\.identity)
            images.pending = nil
            try context.progress(completed: index + 1, total: paths.count)
        }
    }

    /// Task-local checkpoints. A pending paste is never blindly repeated after a failure.
    struct ImageProgress {
        var confirmed: [String] = []
        var pending: Int?

        func validate(_ images: [ImageState]) throws {
            guard images.count >= confirmed.count,
                  Array(images.prefix(confirmed.count).map(\.identity)) == confirmed,
                  images.prefix(confirmed.count).allSatisfy(\.ready) else {
                throw ChannelFailure(code: .verificationFailed, stage: .uploadingAssets,
                    detail: "已确认的知乎图片被删除、替换、重排或不再可用，请检查页面", recovery: .inspectionRequired)
            }
            guard images.count == confirmed.count + (pending == nil ? 0 : 1) else {
                throw ChannelFailure(code: pending == nil ? .verificationFailed : .operationResultUnknown, stage: .uploadingAssets,
                    detail: "知乎附件与任务进度不一致，请检查页面；不会重复粘贴", recovery: .inspectionRequired)
            }
        }
    }

    struct ImageState: Decodable, Equatable {
        let identity: String
        let ready: Bool
    }
    struct PageState: Decodable {
        let title: String
        let body: String
        let titleLimit: Int?
        let titleValid: Bool
        let images: [ImageState]

        func checkContent(_ request: ChannelRequest, allowEmpty: Bool) throws {
            if let titleLimit, titleLimit >= 0, request.title.utf16.count > titleLimit {
                throw ChannelFailure(code: .contentUnsupported, stage: .fillingContent,
                    detail: "标题超过知乎编辑器上限（\(titleLimit)）", recovery: .contentChangeRequired)
            }
            guard titleValid else { throw ChannelFailure(code: .contentUnsupported, stage: .fillingContent,
                detail: "知乎编辑器未接受此标题，请检查标题限制", recovery: .contentChangeRequired) }
            guard title == request.title || (allowEmpty && title.isEmpty) else {
                throw ChannelFailure(code: .verificationFailed, stage: allowEmpty ? .fillingContent : .verifyingContent,
                    detail: "知乎标题与提交内容不一致，已保留页面内容", recovery: .inspectionRequired)
            }
            // CRLF is one line break. Preserve spaces and every empty paragraph.
            func lines(_ text: String) -> String { text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n") }
            guard lines(body) == lines(request.taggedBody) || (allowEmpty && body.isEmpty) else {
                throw ChannelFailure(code: .verificationFailed, stage: allowEmpty ? .fillingContent : .verifyingContent,
                    detail: "知乎正文、段落或标签与提交内容不一致，已保留页面内容", recovery: .inspectionRequired)
            }
        }
    }
    private struct Navigation: Decodable { let loginRequired: Bool?; let composerReady: Bool? }
    private struct PageResult: Decodable { let value: PageState }

    private func readPage(_ bridge: EgoBridge) async throws -> PageState {
        let raw = try await bridge.run("""
            // zhihu:read-page
            const value = await page.evaluate(() => {
              \(Self.readPageSource)
            });
            cliLog(JSON.stringify({ok:true,value}));
            """)
        return try JSONDecoder().decode(PageResult.self, from: Data(raw.utf8)).value
    }

    /// Read Draft's logical blocks: innerText inserts extra visual line breaks around empty blocks.
    private static let readPageSource = """
        if (location.origin !== 'https://www.zhihu.com' || location.pathname !== '/') throw new Error('知乎页面已离开首页');
        const visible = el => !!el && el.getBoundingClientRect().width > 0 && el.getBoundingClientRect().height > 0 && getComputedStyle(el).visibility !== 'hidden';
        const title = document.querySelector('textarea[name="title"]');
        const body = document.querySelector('[contenteditable="true"]');
        if (!visible(title) || !visible(body)) throw new Error('知乎想法编辑器不可操作，请展开后继续');
        const blocks = [...body.querySelectorAll('[data-block="true"]')];
        if (!blocks.length) throw new Error('知乎正文结构发生变化，无法核对段落');
        const root = body.closest('.InputLike');
        if (!root) throw new Error('无法定位知乎附件区域');
        const images = [...root.querySelectorAll('.ImageArea .DraggableTags-tag:not(.DraggableTags-undraggable)')].map(tile => {
          const img = tile.querySelector('img');
          const url = img ? new URL(img.src) : null;
          return {identity: url ? url.origin + url.pathname : '',
            ready: !!img && img.complete && img.naturalWidth > 0 && url.protocol === 'https:' && !tile.querySelector('.CircleLoadingBar')};
        });
        return {title:title.value, body:blocks.map(block => block.textContent).join('\\n'),
          titleLimit:title.hasAttribute('maxlength') ? title.maxLength : null, titleValid:title.validity.valid, images};
        """

    private func waitForImages(_ bridge: EgoBridge, count: Int) async throws {
        do {
            _ = try await bridge.run("""
                // zhihu:wait-images
                await page.waitForFunction(expected => {
                  const state = (() => { \(Self.readPageSource) })();
                  return state.images.length === expected && state.images.every(image => image.ready);
                }, \(count), {timeout:60000});
                cliLog(JSON.stringify({ok:true}));
                """)
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            throw failure(.uploadFailed, .uploadingAssets, "等待第 \(count) 张图片上传失败：\(error.localizedDescription)")
        }
    }

    private func failure(_ code: ChannelErrorCode, _ stage: ChannelStage, _ detail: String) -> ChannelFailure {
        .init(code: code, stage: stage, detail: detail, recovery: .inspectionRequired)
    }

    static func navigate(bridge: EgoBridge, url: String) async throws -> String {
        guard let destination = URL(string: url), destination.scheme == "https",
              destination.host == "www.zhihu.com", destination.path.isEmpty || destination.path == "/",
              destination.query == nil, destination.fragment == nil else {
            throw EgoBridge.BridgeError.toolFailed("知乎想法仅允许打开首页，不能转到文章或其他页面")
        }
        return try await bridge.run("""
            // zhihu:open-editor
            if (await page.url() !== 'https://www.zhihu.com/') await page.goto('https://www.zhihu.com/');
            await page.waitForFunction(() => {
              const visible = el => !!el && el.getBoundingClientRect().width > 0 && el.getBoundingClientRect().height > 0;
              return document.body.innerText.includes('分享此刻的想法') || visible(document.querySelector('textarea[name="title"]')) ||
                visible(document.querySelector('input[type="password"]')) || location.pathname.includes('signin');
            }, undefined, {timeout:15000});
            const loginRequired = await page.evaluate(() => location.pathname.includes('signin') ||
              [...document.querySelectorAll('input[type="password"]')].some(el => el.getBoundingClientRect().width > 0));
            if (loginRequired) cliLog(JSON.stringify({ok:true,loginRequired:true}));
            else {
              const expanded = await page.evaluate(() => {
                const el = document.querySelector('textarea[name="title"]');
                return !!el && el.getBoundingClientRect().width > 0 && el.getBoundingClientRect().height > 0;
              });
              if (!expanded) await page.click('text="分享此刻的想法..."', {label:'展开知乎想法编辑器'});
              await page.waitForSelector('textarea[name="title"]', {state:'visible',timeout:10000});
              await page.waitForSelector('[contenteditable="true"]', {state:'visible',timeout:10000});
              cliLog(JSON.stringify({ok:true,composerReady:true}));
            }
            """)
    }
}
