import Foundation

/// Product editor requirements only. Channel policies belong to adapters.
public enum PlatformRules {
    public static func canStart(body: String, selectedPlatforms: [PlatformID]) -> Bool {
        !selectedPlatforms.isEmpty && !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
