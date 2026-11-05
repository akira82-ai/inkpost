import Foundation

/// 包内资源（适配器脚本、fixture 页面）的公开访问入口。
public enum Resources {
    public static func path(_ name: String, ext: String, sub: String) throws -> String {
        try url(name, ext: ext, sub: sub).path
    }

    public static func url(_ name: String, ext: String, sub: String) throws -> URL {
        guard let u = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: sub) else {
            throw ResourceError.missing("\(sub)/\(name).\(ext)")
        }
        return u
    }

    public enum ResourceError: LocalizedError {
        case missing(String)
        public var errorDescription: String? {
            switch self {
            case .missing(let what): return "缺少包资源 \(what)"
            }
        }
    }
}
