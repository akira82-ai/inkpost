import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

public enum AssetImportError: LocalizedError {
    case limitReached
    public var errorDescription: String? { "最多添加 6 张图片" }
}

/// Original identity and its task-owned, final upload representation.
public struct PreparedAsset: Sendable, Equatable {
    public let sourcePath: String
    public let sourceHash: String
    public let pngPath: String
}

/// Keeps upload files alive through login waits and recovery, then removes only this batch.
final class PreparedAssetBatch: Sendable {
    let assets: [PreparedAsset]
    private let directory: URL
    init(assets: [PreparedAsset], directory: URL) { self.assets = assets; self.directory = directory }
    deinit { try? FileManager.default.removeItem(at: directory) }
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

    /// Called once per dispatch task, off the main actor and before any browser writes.
    static func preparePNGAssets(_ paths: [String]) throws -> PreparedAssetBatch {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("inkpost-upload-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var complete = false
        defer { if !complete { try? FileManager.default.removeItem(at: directory) } }
        var assets: [PreparedAsset] = []
        var converted: [String: String] = [:]
        for (index, path) in paths.enumerated() {
            try Task.checkCancellation()
            do {
                let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
                let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
                let pngPath: String
                if let existing = converted[hash] { pngPath = existing }
                else {
                    let png = try pngData(bytes)
                    try Task.checkCancellation()
                    let url = directory.appendingPathComponent(hash + ".png")
                    try png.write(to: url, options: .atomic)
                    pngPath = url.path
                    converted[hash] = pngPath
                }
                assets.append(.init(sourcePath: path, sourceHash: hash, pngPath: pngPath))
            } catch {
                if error is CancellationError || Task.isCancelled { throw CancellationError() }
                throw ChannelFailure(code: .contentUnsupported, stage: .validatingRequest,
                    detail: "第 \(index + 1) 张图片（\(URL(fileURLWithPath: path).lastPathComponent)）准备失败：\(error.localizedDescription)", recovery: .contentChangeRequired)
            }
        }
        try Task.checkCancellation()
        complete = true
        return PreparedAssetBatch(assets: assets, directory: directory)
    }

    private static func pngData(_ data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw imageError("无法解码图片") }
        guard CGImageSourceGetCount(source) == 1 else { throw imageError("暂不支持动图或多帧图片，请先导出单张静态图片") }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0 else {
            throw imageError("无法读取图片尺寸")
        }
        let orientation = (properties[kCGImagePropertyOrientation] as? Int) ?? 1
        let image: CGImage?
        if orientation == 1 {
            image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        } else {
            // Apply EXIF rotation/mirroring at full resolution; no resizing or cropping.
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(width, height),
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary)
        }
        guard let image, CGImageSourceGetStatus(source) == .statusComplete else { throw imageError("图片像素不完整或无法解码") }
        let swapsAxes = (5...8).contains(orientation)
        guard image.width == (swapsAxes ? height : width), image.height == (swapsAxes ? width : height) else {
            throw imageError("图片方向或像素尺寸未能完整保留")
        }
        try Task.checkCancellation()
        if CGImageSourceGetType(source) as String? == UTType.png.identifier && orientation == 1 {
            _ = try validatedPNG(data)
            return data
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw imageError("无法创建 PNG 编码器")
        }
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 1] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw imageError("PNG 编码失败") }
        let png = output as Data
        _ = try validatedPNG(png)
        return png
    }

    /// Validation only. Upload consumers must never repair or convert invalid input.
    static func validatedPNG(_ data: Data) throws -> Data {
        guard data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              CGImageSourceGetCount(source) == 1,
              CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) != nil,
              CGImageSourceGetStatus(source) == .statusComplete else { throw imageError("上传素材不是有效的单帧 PNG，请重新准备素材") }
        return data
    }

    private static func imageError(_ detail: String) -> NSError {
        NSError(domain: "Inkpost.AssetService", code: 1, userInfo: [NSLocalizedDescriptionKey: detail])
    }
}
