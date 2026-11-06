import Foundation

final class ZhihuChannelAdapter: ChannelAdapter {
    let platform: PlatformID = .zhihu
    let capabilities = ChannelCapabilities(usesTitle: false, requiresLLM: false, maximumImages: 6, entryURL: "https://www.zhihu.com/")
    private var zhihuPendingImage: Int?
    private var zhihuUploaded = 0

    func goal(for request: ChannelRequest) -> String {
        let title = request.title, html = request.html, plain = request.body, tags = request.tags, assets = request.assets
        let tagText = tags.isEmpty ? "无" : tags.map { "#\($0)" }.joined(separator: " ")
        let imageInfo = assets.isEmpty ? "无图片" : "图片 \(assets.count) 张，本地路径：\(assets.joined(separator: "；"))"
        let opening = "把以下内容填入平台创作页，停在草稿状态（绝不点击发布/提交/发送类按钮）。\n- 标题：\(title)\n- 正文纯文本：\(plain)\n- 正文 HTML：\(html)\n- \(imageInfo)\n"

            return opening + """
                - 平台：知乎想法（动态），不发布专栏文章。入口：https://www.zhihu.com/
                - navigate 工具会确定性点击首页“分享此刻的想法…”并等待标题与正文输入框展开；随后 snapshot 定位控件。不要调用不存在的 click 工具，不进入写文章或专栏页面，不猜测选择器。
                - 仅填写正文，不把输入标题自动并入正文，不寻找文章标题框；保留正文全部内容与换行，不改写或截断。以纯文本填写想法编辑器，HTML 仅作内容参考。
                - 图片上传到该想法编辑器对应的图片控件；话题\(tagText == "无" ? "无，跳过" : "（\(tagText)）追加到正文结尾")。图片失败不得报告已填好。
                - 自检完整正文与图片数量，返回实际 body_target 与图片校验位置。停在编辑状态，不假定平台已自动保存草稿，绝不点击“发想法”或其他最终发布按钮。
                - finish(status:"draftReady")。
                """
    }

    @MainActor
    func prepare(request: ChannelRequest, bridge: EgoBridge, config: LLMConfig,
                 onEvent: @escaping @Sendable (String) -> Void) async throws -> EgoBridge.Finish {
        let body = request.body, tags = request.tags, assets = request.assets
        onEvent("打开首页想法编辑器")
        let navigation = try await Self.navigate(bridge: bridge, url: "https://www.zhihu.com/")
        let nav = try JSONSerialization.jsonObject(with: Data(navigation.utf8)) as? [String: Any]
        if nav?["loginRequired"] as? Bool == true { return .init(status: "needLogin", message: "请登录知乎后继续此渠道") }
        try Task.checkCancellation()
        let text = body + (tags.isEmpty ? "" : "\n\n" + tags.map { "#" + $0 }.joined(separator: " "))
        _ = try await bridge.run("""
            const expected = \(bridge.jsStr(text));
            const current = await page.evaluate(() => document.querySelector('[contenteditable=true]').innerText);
            const normalize = value => value.replace(/\\s+/g, '');
            if (normalize(current) && normalize(current) !== normalize(expected)) throw new Error('知乎已有其他正文，已保留，请手动检查后重新开始');
            if (!normalize(current)) {
              await page.click('[contenteditable="true"]', {label:'填写完整想法正文'});
              await page.keyboard.paste(expected);
            }
            cliLog(JSON.stringify({ok:true}));
            """)
        let clipboard = ImageClipboardSession()
        defer { clipboard.restore() }
        for (index, path) in assets.enumerated() {
            try Task.checkCancellation()
            if index < zhihuUploaded { continue }
            let count = try await zhihuImageCount(bridge)
            if zhihuPendingImage == index {
                guard count == index + 1 else { throw EgoBridge.BridgeError.toolFailed("上次图片粘贴结果不确定，请检查知乎附件后重新开始，未重复粘贴") }
            } else {
                guard count == index else { throw EgoBridge.BridgeError.toolFailed("知乎已有图片与任务不一致，请检查后重新开始") }
                try clipboard.writePNG(path: path)
                zhihuPendingImage = index
                onEvent("粘贴图片 \(index + 1)/\(assets.count)")
                _ = try await bridge.run("""
                    await page.click('[contenteditable="true"]', {label:'粘贴下一张想法图片'});
                    await page.keyboard.press('Meta+V');
                    cliLog(JSON.stringify({ok:true}));
                    """)
            }
            try await waitForZhihuImages(bridge, count: index + 1)
            try Task.checkCancellation()
            zhihuUploaded = index + 1; zhihuPendingImage = nil
            onEvent("图片 \(index + 1)/\(assets.count) 上传完成")
        }
        try await waitForZhihuImages(bridge, count: assets.count)
        var result = EgoBridge.Finish(status: "draftReady", message: "正文及 \(assets.count) 张图片已填好，请检查后亲手发想法", draftURL: "https://www.zhihu.com/")
        result.bodyTarget = "[contenteditable=\"true\"]"
        return result
    }

    private func zhihuImageCount(_ bridge: EgoBridge) async throws -> Int {
        let raw = try await bridge.evaluate(js: "document.querySelector('[contenteditable=true]').closest('.InputLike').querySelectorAll('.ImageArea .DraggableTags-tag:not(.DraggableTags-undraggable)').length")
        let value = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any]
        guard let count = value?["value"] as? Int else { throw EgoBridge.BridgeError.toolFailed("无法读取知乎附件数量") }
        return count
    }

    private func waitForZhihuImages(_ bridge: EgoBridge, count: Int) async throws {
        _ = try await bridge.run("""
            await page.waitForFunction(expected => {
              const editor = document.querySelector('[contenteditable=true]');
              if (!editor) return false;
              const tiles = [...editor.closest('.InputLike').querySelectorAll('.ImageArea .DraggableTags-tag:not(.DraggableTags-undraggable)')];
              return tiles.length === expected && tiles.every(tile => {
                const image = tile.querySelector('img');
                return image && image.complete && image.naturalWidth > 0 && image.src.startsWith('https:') && !tile.querySelector('.CircleLoadingBar');
              });
            }, \(count), {timeout:60000});
            cliLog(JSON.stringify({ok:true}));
            """)
    }

    static func navigate(bridge: EgoBridge, url: String) async throws -> String {
            guard let destination = URL(string: url), destination.scheme == "https",
                  destination.host == "www.zhihu.com", destination.path.isEmpty || destination.path == "/",
                  destination.query == nil, destination.fragment == nil else {
                throw EgoBridge.BridgeError.toolFailed("知乎想法仅允许打开首页，不能转到文章或其他页面")
            }
            return try await bridge.run("""
                if (await page.url() !== 'https://www.zhihu.com/') {
                  await page.goto('https://www.zhihu.com/');
                }
                await page.waitForFunction(() =>
                  document.body.innerText.includes('分享此刻的想法') ||
                  document.querySelector('textarea[name="title"]') ||
                  document.querySelector('input[type="password"]') ||
                  location.pathname.includes('signin'), undefined, { timeout: 15000 });
                const loginRequired = await page.evaluate(() =>
                  location.pathname.includes('signin') || !!document.querySelector('input[type="password"]'));
                if (loginRequired) {
                  cliLog(JSON.stringify({ok:true, loginRequired:true}));
                } else {
                  const expanded = await page.evaluate(() => {
                    const el = document.querySelector('textarea[name="title"]');
                    return !!el && el.getBoundingClientRect().width > 0;
                  });
                  if (!expanded) {
                    await page.click('text="分享此刻的想法..."', { label: '展开知乎想法编辑器' });
                  }
                  await page.waitForSelector('textarea[name="title"]', { state: 'visible', timeout: 10000 });
                  await page.waitForSelector('[contenteditable="true"]', { state: 'visible', timeout: 10000 });
                  cliLog(JSON.stringify({ok:true, url:await page.url(), composerReady:true,
                    titleTarget:'textarea[name="title"]', bodyTarget:'[contenteditable="true"]'}));
                }
                """);
        }

    @MainActor
    func verify(bridge: EgoBridge, result: EgoBridge.Finish, title: String, body: String, imageCount: Int) async throws {
        try await DraftVerifier.verify(bridge: bridge, result: result, title: title, body: body, imageCount: 0, usesTitle: false)
        try await waitForZhihuImages(bridge, count: imageCount)
    }
}
