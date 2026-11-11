import AppKit

/// Own the marked clipboard write; the operation must focus and send Meta+V only.
@MainActor
public enum ClipboardPasteService {
    public static func withTextPaste<T>(_ text: String, _ operation: () async throws -> T) async throws -> T {
        try await withTextPaste(text, clipboard: .general, operation)
    }

    static func withTextPaste<T>(_ text: String, clipboard: NSPasteboard,
                                _ operation: () async throws -> T) async throws -> T {
        let lease = try ImageClipboardSession.acquire(clipboard: clipboard)
        defer { lease.restore() }
        try lease.writeText(text)
        return try await operation()
    }
}
