import Foundation

/// A single lease covers focus + native paste. Adapters supply the target interaction.
@MainActor
public enum ClipboardPasteService {
    public static func withTextPaste<T>(_ operation: () async throws -> T) async throws -> T {
        let lease = try ImageClipboardSession.acquire()
        defer { lease.restore() }
        try Task.checkCancellation()
        return try await operation()
    }
}
