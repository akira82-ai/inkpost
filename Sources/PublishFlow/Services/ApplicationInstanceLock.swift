import Foundation
import Darwin

/// A stable per-user inode, shared by bundled copies and direct executable launches.
/// Never unlink it: the kernel releases flock on exit (including crashes), not the file's presence.
final class ApplicationInstanceLock {
    struct Owner: Codable, Equatable {
        let pid: Int32
        let token: UUID
    }

    let owner = Owner(pid: getpid(), token: UUID())
    private let descriptor: Int32
    private(set) var isOwner = false

    static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "Inkpost/Runtime", directoryHint: .isDirectory)
    }

    init(directory: URL = ApplicationInstanceLock.directory) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        descriptor = open(directory.appending(path: "instance.lock").path,
                          O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw Self.systemError("open instance lock") }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_uid == getuid(),
              info.st_mode & S_IFMT == S_IFREG else {
            close(descriptor)
            throw NSError(domain: "Inkpost.Instance", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "实例锁不是当前用户的普通文件"])
        }
    }

    deinit { close(descriptor) }

    func acquire() throws -> Bool {
        if isOwner { return true }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            if errno == EWOULDBLOCK { return false }
            throw Self.systemError("acquire instance lock")
        }
        do {
            let data = try JSONEncoder().encode(owner)
            guard ftruncate(descriptor, 0) == 0 else { throw Self.systemError("truncate instance metadata") }
            try data.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    let count = pwrite(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset, off_t(offset))
                    if count < 0 && errno == EINTR { continue }
                    guard count > 0 else { throw Self.systemError("write instance metadata") }
                    offset += count
                }
            }
            isOwner = true
            return true
        } catch {
            flock(descriptor, LOCK_UN)
            throw error
        }
    }

    func readOwner() throws -> Owner? {
        var bytes = [UInt8](repeating: 0, count: 4096)
        let count = pread(descriptor, &bytes, bytes.count, 0)
        guard count >= 0 else { throw Self.systemError("read instance metadata") }
        // An owner may still be writing its initial record. Retry, rather than treating PID as a lock.
        guard count > 0, let value = try? JSONDecoder().decode(Owner.self, from: Data(bytes.prefix(count))),
              value.pid > 0 else { return nil }
        return value
    }

    private static func systemError(_ operation: String) -> NSError {
        let code = errno
        return NSError(domain: NSPOSIXErrorDomain, code: Int(code),
                       userInfo: [NSLocalizedDescriptionKey: "\(operation): \(String(cString: strerror(code)))"])
    }
}
