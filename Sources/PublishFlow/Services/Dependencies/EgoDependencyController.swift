import AppKit
import Observation
import PublishKit

/// Observes the dependency without claiming Spaces or changing browser pages.
@MainActor @Observable
final class EgoDependencyController {
    private(set) var status = "正在检测"
    private(set) var message: String?
    private(set) var isChecking = false
    private(set) var isReady = false
    private var installedURL: URL?
    var actionTitle: String { installedURL == nil ? "下载安装" : "打开并重新检测" }

    func refresh() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        message = nil
        isReady = false
        installedURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.citrolabs.ego.lite")
        guard installedURL != nil else { status = "未安装"; return }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.citrolabs.ego.lite").contains(where: { !$0.isTerminated }) else {
            status = "未启动"
            return
        }
        do {
            // A trivial runtime call checks connectivity without touching user task ownership.
            let result = try await EgoLiteEngine().runRaw(script: "cliLog(JSON.stringify({ok:true}));", timeout: 10)
            guard result.bool("ok") == true else { throw EgoLiteEngine.EngineError.timeout }
            status = "已就绪"
            isReady = true
        } catch {
            status = "连接异常"
            message = error.localizedDescription
        }
    }

    func performAction() {
        guard !isChecking else { return }
        let applicationURL = installedURL
        isChecking = true
        Task {
            do {
                status = applicationURL == nil ? "下载安装中" : "正在启动"
                let target: URL
                if let applicationURL { target = applicationURL }
                else { target = try await EgoDependencyInstaller.install() }
                _ = try await NSWorkspace.shared.openApplication(at: target, configuration: NSWorkspace.OpenConfiguration())
                isChecking = false
                await refresh()
            } catch {
                isChecking = false
                status = applicationURL == nil ? "安装失败" : "启动失败"
                message = error.localizedDescription
            }
        }
    }
}
