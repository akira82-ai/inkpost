import Foundation

/// 本地优先存储：`~/Library/Application Support/PublishFlow/posts/<postId>/`
/// 每帖一个目录：post.json（内容+状态）、assets/（素材副本）。
/// 目录结构对 Obsidian/Markdown 工作流友好，后续可监听 vault。
public struct PostStore {
    public let root: URL

    public init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.root = base.appendingPathComponent("PublishFlow", isDirectory: true)
        }
    }

    public var postsDir: URL { root.appendingPathComponent("posts", isDirectory: true) }

    public func ensureRoot() throws {
        try FileManager.default.createDirectory(at: postsDir, withIntermediateDirectories: true)
    }

    public func listPosts() throws -> [Post] {
        try ensureRoot()
        let items = try FileManager.default.contentsOfDirectory(at: postsDir, includingPropertiesForKeys: nil)
        return items
            .filter { $0.hasDirectoryPath && $0.lastPathComponent != ".DS_Store" }
            .compactMap { url in
                let meta = url.appendingPathComponent("post.json")
                guard let data = try? Data(contentsOf: meta) else { return nil }
                return try? JSONDecoder.decoderWithDates.decode(Post.self, from: data)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func save(_ post: inout Post) throws {
        try ensureRoot()
        let dir = postsDir.appendingPathComponent(post.id, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        post.updatedAt = Date()
        let data = try JSONEncoder.encoderWithDates.encode(post)
        try data.write(to: dir.appendingPathComponent("post.json"), options: .atomic)
    }

    /// 任务目录约定：assets/ 素材、task.json 任务、events.ndjson 适配器事件、boot-*.mjs 引导脚本
    public func taskDir(for postID: String) -> URL {
        postsDir.appendingPathComponent(postID, isDirectory: true)
    }
}

extension JSONEncoder {
    static let encoderWithDates: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}

extension JSONDecoder {
    static let decoderWithDates: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
