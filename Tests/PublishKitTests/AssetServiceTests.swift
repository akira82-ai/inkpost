import Foundation
import Testing
import AppKit
import ImageIO
import UniformTypeIdentifiers
@testable import PublishKit

struct AssetServiceTests {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
    @Test func duplicateBytesDoNotConsumeSlots() throws {
        let service = AssetService(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let first = try #require(try service.importData(png, existing: []))
        #expect(try service.importData(png, existing: [first]) == nil)
    }
    @Test func rejectsInvalidImages() {
        let service = AssetService()
        #expect(throws: (any Error).self) { try service.importData(Data("not an image".utf8), existing: []) }
    }
    @Test func limitAppliesAfterDeduplication() throws {
        let service = AssetService(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        var paths: [String] = []
        for value in UInt8(0)..<6 {
            var bytes = png; bytes.append(value)
            paths.append(try #require(try service.importData(bytes, existing: paths)))
        }
        var duplicate = png; duplicate.append(0)
        #expect(try service.importData(duplicate, existing: paths) == nil)
        var seventh = png; seventh.append(7)
        #expect(throws: (any Error).self) { try service.importData(seventh, existing: paths) }
    }

    @Test(arguments: [UTType.png, .jpeg, .tiff, .heic])
    func preparesRealPNGWithoutChangingSource(_ type: UTType) throws {
        let file = try testAssetFile(type: type)
        let original = try Data(contentsOf: file)
        let batch = try AssetService.preparePNGAssets([file.path, file.path])
        #expect(batch.assets.count == 2)
        #expect(batch.assets[0] == batch.assets[1])
        let output = try Data(contentsOf: URL(fileURLWithPath: batch.assets[0].pngPath))
        #expect(try AssetService.validatedPNG(output) == output)
        #expect(try Data(contentsOf: file) == original)
        #expect(batch.assets[0].sourcePath == file.path)
        #expect(batch.assets[0].pngPath != file.path)
        let source = try #require(CGImageSourceCreateWithData(output as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 3 && image.height == 2)
        if type == .png { #expect(output == original) }
        if type == .png || type == .tiff {
            let bitmap = try #require(NSBitmapImageRep(data: output))
            let color = try #require(bitmap.colorAt(x: 0, y: 0))
            #expect(abs(color.alphaComponent - 0.5) < 0.02)
        }
    }

    @Test func appliesOrientationWithoutResizing() throws {
        let file = try testAssetFile(type: .jpeg, orientation: 6)
        let batch = try AssetService.preparePNGAssets([file.path])
        let source = try #require(CGImageSourceCreateWithURL(URL(fileURLWithPath: batch.assets[0].pngPath) as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 2 && image.height == 3)
    }

    @Test func rejectsMultiframeAndInvalidImages() throws {
        let multi = try testAssetFile(type: .tiff, frames: 2)
        let invalid = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try Data("not PNG".utf8).write(to: invalid)
        for path in [multi.path, invalid.path, invalid.path + ".missing"] {
            do { _ = try AssetService.preparePNGAssets([path]); Issue.record("Invalid asset accepted") }
            catch { #expect((error as? ChannelFailure)?.stage == .validatingRequest) }
        }
        #expect(throws: (any Error).self) { try AssetService.validatedPNG(Data(contentsOf: multi)) }
    }

    @Test func preparedFilesLiveExactlyAsLongAsTheirBatch() throws {
        let file = try testAssetFile()
        var batch: PreparedAssetBatch? = try AssetService.preparePNGAssets([file.path])
        let path = try #require(batch?.assets.first?.pngPath)
        #expect(FileManager.default.fileExists(atPath: path))
        batch = nil
        #expect(!FileManager.default.fileExists(atPath: path))
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func cancelledPreparationDoesNotReturnAssets() async throws {
        let file = try testAssetFile()
        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try AssetService.preparePNGAssets([file.path])
        }
        do { _ = try await operation.value; Issue.record("Cancellation swallowed") }
        catch { #expect(error is CancellationError) }
    }
}

func testAssetFile(type: UTType = .png, orientation: Int = 1, frames: Int = 1) throws -> URL {
    let context = try #require(CGContext(data: nil, width: 3, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.4, alpha: 0.5))
    context.fill(CGRect(x: 0, y: 0, width: 3, height: 2))
    let image = try #require(context.makeImage())
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("asset-test-\(UUID().uuidString).\(type.preferredFilenameExtension ?? "image")")
    let destination = try #require(CGImageDestinationCreateWithURL(file as CFURL, type.identifier as CFString, frames, nil))
    for _ in 0..<frames {
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
    }
    #expect(CGImageDestinationFinalize(destination))
    return file
}
