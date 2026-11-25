import Foundation

/// Native editor operations only. Unknown attachment controls fail before new content is pasted.
enum RetryEditorReset {
    @MainActor
    static func clear(_ bridge: EgoBridge, editor: String, attachments: String, count: Int,
                      title: String? = nil) async throws {
        let titleScript = title.map { "await page.fill(\(bridge.jsStr($0)), '');" } ?? ""
        _ = try await bridge.run("""
        // retry:clear-editor
        const tiles = \(bridge.jsStr(attachments));
        for (let index = 0; index < \(count); index++) {
            await page.hover(tiles + ' >> nth=0', {label:'显示图片移除入口'});
            await page.waitForFunction(selector => {
                const tile = document.querySelector(selector);
                const container = tile?.tagName === 'IMG' ? tile.parentElement : tile;
                return !!container && [...container.querySelectorAll('button, [role="button"], [aria-label], [title]')]
                    .some(el => el.checkVisibility({checkOpacity:true, checkVisibilityCSS:true}) &&
                        /^(删除|移除)(图片|附件|媒体)?$|^(remove|delete)( image| media| attachment)?$/i.test(
                            (el.getAttribute('aria-label') || el.getAttribute('title') || el.textContent || '').trim()));
            }, tiles, {timeout:5000});
            const target = await page.evaluate(selector => {
                const tile = document.querySelector(selector);
                if (!tile) throw new Error('待移除附件不存在');
                const container = tile.tagName === 'IMG' ? tile.parentElement : tile;
                const controls = [...container.querySelectorAll('button, [role="button"], [aria-label], [title]')]
                    .filter(el => el.checkVisibility({checkOpacity:true, checkVisibilityCSS:true}))
                    .filter(el => /^(删除|移除)(图片|附件|媒体)?$|^(remove|delete)( image| media| attachment)?$/i.test(
                        (el.getAttribute('aria-label') || el.getAttribute('title') || el.textContent || '').trim()));
                if (controls.length !== 1) throw new Error('无法唯一识别附件移除控件，请手工处理');
                const path = el => {
                    if (el === document.documentElement) return '/html[1]';
                    const siblings = [...el.parentElement.children].filter(node => node.tagName === el.tagName);
                    return path(el.parentElement) + '/' + el.tagName.toLowerCase() + '[' + (siblings.indexOf(el) + 1) + ']';
                };
                return 'xpath=' + path(controls[0]);
            }, tiles);
            await channelClick(target, {label:'清空编辑区旧附件'});
            await page.waitForFunction(({selector, expected}) => document.querySelectorAll(selector).length === expected,
                {selector:tiles, expected:\(count) - index - 1}, {timeout:10000});
        }
        \(titleScript)
        await page.focus(\(bridge.jsStr(editor)));
        await page.keyboard.press('Meta+A');
        await page.keyboard.press('Backspace');
        await page.waitForFunction(({editor, attachments, title}) => {
            const field = document.querySelector(editor);
            const heading = title ? document.querySelector(title) : null;
            return !!field && (('value' in field ? field.value : field.textContent) === '') &&
                document.querySelectorAll(attachments).length === 0 && (!title || heading?.value === '');
        }, {editor:\(bridge.jsStr(editor)), attachments:tiles, title:\(title.map { bridge.jsStr($0) } ?? "null")}, {timeout:10000});
        cliLog(JSON.stringify({ok:true}));
        """)
    }
}
