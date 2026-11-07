import AppKit

/// Owns only this operation's clipboard writes; preserves newer user copies.
@MainActor
final class ImageClipboardSession {
    private static var occupied = false
    private let clipboard: NSPasteboard
    private var released = false

    static func acquire(clipboard: NSPasteboard = .general) throws -> ImageClipboardSession {
        guard !occupied else { throw ChannelFailure(code: .executionFailed, stage: .uploadingAssets, detail: "另一项粘贴操作正在使用剪贴板", recovery: .retryAllowed) }
        occupied = true
        return ImageClipboardSession(clipboard: clipboard)
    }
    private let initialChange: Int
    private let saved: [[(NSPasteboard.PasteboardType, Data)]]
    private var ownedChange: Int?

    private init(clipboard: NSPasteboard) {
        self.clipboard = clipboard
        initialChange = clipboard.changeCount
        saved = (clipboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }

    func writePNG(path: String) throws {
        try Task.checkCancellation()
        guard !released else { throw ChannelFailure(code: .invalidCommand, stage: .uploadingAssets, detail: "剪贴板会话已结束", recovery: .notRecoverable) }
        let png = try AssetService.validatedPNG(Data(contentsOf: URL(fileURLWithPath: path)))
        try Task.checkCancellation()
        guard clipboard.changeCount == (ownedChange ?? initialChange) else {
            throw EgoBridge.BridgeError.toolFailed("剪贴板被修改，已停止图片粘贴，请重试")
        }
        clipboard.clearContents()
        ownedChange = clipboard.changeCount
        let written = clipboard.setData(png, forType: .png)
        ownedChange = clipboard.changeCount
        guard written else { throw EgoBridge.BridgeError.toolFailed("无法写入图片剪贴板") }
    }

    func restore() {
        guard !released else { return }
        released = true
        defer { Self.occupied = false }
        guard let ownedChange, clipboard.changeCount == ownedChange else { return }
        clipboard.clearContents()
        let items = saved.map { values in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        }
        clipboard.writeObjects(items)
    }
}
