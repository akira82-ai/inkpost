import Foundation
import Testing
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
}
