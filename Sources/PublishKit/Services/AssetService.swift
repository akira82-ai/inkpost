import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

public enum AssetImportError: LocalizedError {
    case limitReached
    public var errorDescription: String? { "最多添加 6 张图片" }
}

public final class AssetService {
    private let root: URL
    public init(root: URL = FileManager.default.temporaryDirectory.appendingPathComponent("inkpost-assets")) { self.root = root }
    public func importData(_ data: Data, existing: [String]) throws -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else {
            throw NSError(domain: "Inkpost", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法读取这张图片"])
        }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        for path in existing {
            let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
            if SHA256.hash(data: bytes) == SHA256.hash(data: data) { return nil }
        }
        guard existing.count < 6 else { throw AssetImportError.limitReached }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let type = CGImageSourceGetType(source) as String? ?? ""
        let ext = UTType(type)?.preferredFilenameExtension ?? "image"
        let url = root.appendingPathComponent(hash + "." + ext)
        try data.write(to: url, options: .atomic)
        return url.path
    }
    public func previewData(_ path: String) throws -> Data { try Data(contentsOf: URL(fileURLWithPath: path)) }
    public func importFile(_ path: String, existing: [String]) throws -> String? {
        try importData(Data(contentsOf: URL(fileURLWithPath: path)), existing: existing)
    }
}
