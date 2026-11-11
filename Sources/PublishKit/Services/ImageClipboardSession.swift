import AppKit

/// Owns only this operation's clipboard writes; preserves newer user copies.
@MainActor
final class ImageClipboardSession {
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    private static var occupied = false
    private let clipboard: NSPasteboard
    private var released = false

    static func acquire(clipboard: NSPasteboard = .general) throws -> ImageClipboardSession {
        guard !occupied else { throw ChannelFailure(code: .executionFailed, stage: .uploadingAssets, detail: "另一项粘贴操作正在使用剪贴板", recovery: .retryAllowed) }
        let session = try ImageClipboardSession(clipboard: clipboard)
        occupied = true
        return session
    }
    private let initialChange: Int
    private let saved: [[(NSPasteboard.PasteboardType, Data)]]
    private var ownedChange: Int?

    private init(clipboard: NSPasteboard) throws {
        self.clipboard = clipboard
        initialChange = clipboard.changeCount
        saved = try (clipboard.pasteboardItems ?? []).map { item in
            try item.types.map { type in
                guard let data = item.data(forType: type) else {
                    throw EgoBridge.BridgeError.toolFailed("无法完整保存原剪贴板，已停止粘贴")
                }
                return (type, data)
            }
        }
        guard clipboard.changeCount == initialChange else {
            throw EgoBridge.BridgeError.toolFailed("保存期间剪贴板被修改，已停止粘贴")
        }
    }

    func writePNG(path: String) throws {
        try Task.checkCancellation()
        guard !released else { throw ChannelFailure(code: .invalidCommand, stage: .uploadingAssets, detail: "剪贴板会话已结束", recovery: .notRecoverable) }
        let png = try AssetService.validatedPNG(Data(contentsOf: URL(fileURLWithPath: path)))
        try write(png, type: .png)
    }

    func writeText(_ text: String) throws {
        try write(Data(text.utf8), type: .string)
    }

    private func write(_ data: Data, type: NSPasteboard.PasteboardType) throws {
        try Task.checkCancellation()
        guard !released else { throw EgoBridge.BridgeError.toolFailed("剪贴板会话已结束") }
        guard clipboard.changeCount == (ownedChange ?? initialChange) else {
            throw EgoBridge.BridgeError.toolFailed("剪贴板被修改，已停止粘贴，请重试")
        }
        // Publish payload and marker together; never expose an unmarked temporary item.
        let item = NSPasteboardItem()
        guard item.setData(data, forType: type), item.setData(Data(), forType: Self.transientType) else {
            throw EgoBridge.BridgeError.toolFailed("无法准备临时剪贴板内容")
        }
        clipboard.clearContents()
        ownedChange = clipboard.changeCount
        let written = clipboard.writeObjects([item])
        ownedChange = clipboard.changeCount
        guard written else { throw EgoBridge.BridgeError.toolFailed("无法写入临时剪贴板内容") }
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
