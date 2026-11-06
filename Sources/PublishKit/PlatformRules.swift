import Foundation

/// Compatibility facade; platform instructions belong to their adapters.
public enum PlatformRules {
    public static func goal(for platform: PlatformID, title: String, html: String, plain: String, tags: [String], assets: [String]) -> String {
        guard let adapter = ChannelRegistry.standard.adapter(for: platform) else { return "" }
        return adapter.goal(for: .init(title: title, body: plain, html: html, tags: tags, assets: assets))
    }
}
