import AppKit

/// Owns only this operation's clipboard writes; preserves newer user copies.
@MainActor
final class ImageClipboardSession {
    private let clipboard = NSPasteboard.general
    private let initialChange: Int
    private let saved: [[(NSPasteboard.PasteboardType, Data)]]
    private var ownedChange: Int?

    init() {
        initialChange = clipboard.changeCount
        saved = (clipboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }

    func writePNG(path: String) throws {
        guard let image = NSImage(contentsOfFile: path), let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else {
            throw EgoBridge.BridgeError.toolFailed("无法读取待上传图片")
        }
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
