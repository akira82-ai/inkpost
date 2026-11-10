import Foundation
import OSLog

/// LaunchServices normally reopens a bundle, but direct binaries and copies need their own guard.
/// Only the lock owner constructs SwiftUI state. A duplicate exits after an acknowledged handoff.
@MainActor
final class ApplicationInstance: NSObject {
    enum Request: String { case activate, stop }
    enum Outcome { case primary, activatedExisting, stopped }
    private static let requestName = Notification.Name("com.publishflow.app.instance.request")
    private static let responseName = Notification.Name("com.publishflow.app.instance.response")
    private static let logger = Logger(subsystem: "com.publishflow.app", category: "instance")
    private let lock: ApplicationInstanceLock
    private let center = DistributedNotificationCenter.default()
    private var acknowledgedOwner: String?
    private var activationHandler: (() -> Bool)?
    private var stopHandler: (() -> Void)?
    private var pendingRequests: Set<String> = []

    init(directory: URL = ApplicationInstanceLock.directory) throws {
        lock = try ApplicationInstanceLock(directory: directory)
        super.init()
    }

    /// Called before App.main: no window, menu item, model or dispatch task exists in a duplicate.
    func start(request: Request = .activate, timeout: TimeInterval = 8) throws -> Outcome {
        let requestID = UUID().uuidString
        acknowledgedOwner = nil
        // Selector delivery stays on the main run loop without an OperationQueue hop,
        // including while a synchronous startup handshake is pumping that run loop.
        center.addObserver(self, selector: #selector(receiveResponse(_:)), name: Self.responseName,
                           object: requestID, suspensionBehavior: .deliverImmediately)
        defer { center.removeObserver(self, name: Self.responseName, object: requestID) }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var nextPost: TimeInterval = 0
        while true {
            if try lock.acquire() {
                if request == .stop { return .stopped }
                listen()
                Self.logger.notice("Primary instance started, pid=\(self.lock.owner.pid)")
                return .primary
            }
            if let owner = try lock.readOwner() {
                if request == .activate, acknowledgedOwner == owner.token.uuidString {
                    Self.logger.notice("Activated existing instance, pid=\(owner.pid)")
                    return .activatedExisting
                }
                let now = ProcessInfo.processInfo.systemUptime
                if now >= nextPost {
                    center.postNotificationName(Self.requestName, object: owner.token.uuidString,
                                                userInfo: ["id": requestID, "action": request.rawValue], deliverImmediately: true)
                    nextPost = now + 0.25
                }
            }
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                Self.logger.error("Existing instance did not respond; no second instance started")
                throw NSError(domain: "Inkpost.Instance", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "已有墨驿实例未响应，未启动第二个实例。请检查现有应用；内容和任务未被终止。"
                ])
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }

    func whenReady(activate: @escaping () -> Bool, stop: @escaping () -> Void) {
        activationHandler = activate
        stopHandler = stop
        if !pendingRequests.isEmpty, activate() {
            for requestID in pendingRequests { acknowledge(requestID) }
            pendingRequests.removeAll()
        }
    }

    private func listen() {
        center.addObserver(self, selector: #selector(receive(_:)), name: Self.requestName,
                           object: lock.owner.token.uuidString, suspensionBehavior: .deliverImmediately)
    }

    @objc private func receiveResponse(_ notification: Notification) {
        acknowledgedOwner = notification.userInfo?["owner"] as? String
    }

    @objc private func receive(_ notification: Notification) {
        guard let id = notification.userInfo?["id"] as? String, UUID(uuidString: id) != nil,
              let action = notification.userInfo?["action"] as? String, let request = Request(rawValue: action) else { return }
        switch request {
        case .activate:
            guard let activationHandler else { pendingRequests.insert(id); return }
            guard activationHandler() else { return }
            pendingRequests.remove(id)
            acknowledge(id)
        case .stop:
            // The build script invokes this only after the replacement build is signed and verified.
            stopHandler?()
        }
    }

    private func acknowledge(_ requestID: String) {
        center.postNotificationName(Self.responseName, object: requestID,
                                    userInfo: ["owner": lock.owner.token.uuidString], deliverImmediately: true)
    }

    func stopListening() {
        center.removeObserver(self, name: Self.requestName, object: lock.owner.token.uuidString)
        activationHandler = nil
        stopHandler = nil
    }
}
