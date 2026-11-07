import Foundation

public struct DispatchSettings {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func selectedPlatforms() -> [PlatformID] {
        guard let saved = defaults.stringArray(forKey: "inkpost.channels") else { return [.zhihu, .x] }
        return saved.compactMap(PlatformID.init(rawValue:)).filter { $0.isAvailable }
    }
    public func savePlatforms(_ platforms: [PlatformID]) {
        defaults.set(platforms.map(\.rawValue), forKey: "inkpost.channels")
    }
}
