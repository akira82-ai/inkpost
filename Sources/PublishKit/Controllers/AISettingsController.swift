import Foundation
import Observation

@MainActor @Observable
public final class AISettingsController {
    public var configuration = AIConfiguration()
    public var key = ""
    public var models: [String] = []
    public private(set) var message: String?
    public private(set) var loaded = false
    public private(set) var isConnecting = false
    @ObservationIgnored private var request: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    public init() {}

    public func load() {
        configuration = AISettings().load()
        do { key = try AISettings.readKey(); loaded = true }
        catch { message = error.localizedDescription }
    }
    public func save() {
        do {
            try AISettings().save(configuration, key: key)
            message = "已保存"
        } catch { message = error.localizedDescription }
    }
    public func invalidate() {
        request?.cancel()
        request = nil
        isConnecting = false
        generation = UUID()
        message = nil
    }
    public func fetchModels() {
        run { configuration, key in
            let result = try await AIClient.shared.models(configuration: configuration, key: key)
            return ("已获取 \(result.count) 个模型", result)
        }
    }
    public func testConnection() {
        run { configuration, key in
            _ = try await AIClient.shared.complete(configuration: configuration, key: key,
                system: "This is a connection test. Reply OK.", text: "OK")
            return ("连接成功", nil)
        }
    }
    private func run(_ operation: @escaping (AIConfiguration, String) async throws -> (String, [String]?)) {
        invalidate()
        let token = generation
        let snapshot = configuration
        let credential = key
        isConnecting = true
        message = "正在连接…"
        request = Task { @MainActor in
            defer {
                if generation == token { request = nil; isConnecting = false }
            }
            do {
                let (status, result) = try await operation(snapshot, credential)
                guard generation == token, !Task.isCancelled else { return }
                message = status
                if let result { models = result }
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                message = error.localizedDescription
            }
        }
    }
}
