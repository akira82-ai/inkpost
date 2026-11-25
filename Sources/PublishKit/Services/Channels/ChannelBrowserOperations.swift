import Foundation

/// Shared pacing for explicit channel clicks. Application-specific postconditions stay in adapters.
enum ChannelBrowserOperations {
    static let minimumClickDelay = 300
    static let maximumClickDelay = 800

    static let clickSource = """
    const channelClick = async (target, options) => {
        const receipt = await page.click(target, options);
        const delay = \(minimumClickDelay) + Math.floor(Math.random() * \(maximumClickDelay - minimumClickDelay + 1));
        await page.waitForTimeout(delay);
        return receipt;
    };
    const waitForEditorFocus = async selector => {
        await page.waitForFunction(target => {
            const field = document.querySelector(target);
            return !!field && !field.disabled && !field.readOnly &&
                (document.activeElement === field || field.contains(document.activeElement));
        }, selector, {timeout:5000});
    };
    """

    /// Reveal the attachment region without moving focus or editing the draft.
    @MainActor
    static func inspectAttachments(_ context: ChannelExecutionContext, editor: String, attachments: String) async throws {
        try Task.checkCancellation()
        _ = try await context.bridge.run("""
        // channel:inspect-attachments
        const target = {editor: \(context.bridge.jsStr(editor)), attachments: \(context.bridge.jsStr(attachments))};
        await page.evaluate(({editor, attachments}) => {
            const editors = [...document.querySelectorAll(editor)].filter(node => node.checkVisibility());
            if (editors.length !== 1) throw new Error('无法唯一定位待检查的编辑器');
            const field = editors[0];
            const tiles = document.querySelectorAll(attachments);
            if (!tiles.length) throw new Error('未找到本次任务的图片附件');
            const last = tiles[tiles.length - 1];
            const overflows = node => node.scrollHeight > node.clientHeight + 2;
            if (overflows(field)) field.scrollTop = field.scrollHeight;

            // Only scroll an editor ancestor when its overflow clips the attachment.
            for (let node = field.parentElement; node && node !== document.body; node = node.parentElement) {
                if (!node.contains(last) || node === document.scrollingElement ||
                    !overflows(node) || !/^(auto|scroll)$/.test(getComputedStyle(node).overflowY)) continue;
                if (last.getBoundingClientRect().bottom > node.getBoundingClientRect().bottom) {
                    node.scrollTop = node.scrollHeight;
                }
            }
            const rect = last.getBoundingClientRect();
            if (rect.top < 0 || rect.bottom > innerHeight) {
                last.scrollIntoView({block:'nearest', inline:'nearest', behavior:'instant'});
            }
        }, target);
        cliLog(JSON.stringify({ok:true}));
        """)
        try Task.checkCancellation()
    }
}
