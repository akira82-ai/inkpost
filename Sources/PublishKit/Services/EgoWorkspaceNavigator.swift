import AppKit

enum WorkspaceNavigationError: LocalizedError {
    case automationDenied
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .automationDenied:
            return "请在系统设置 → 隐私与安全性 → 自动化中，允许墨驿读取 ego lite 当前窗口，然后重试。"
        case .failed(let detail): return detail
        }
    }
}

/// Native application activation is independent of browser task/Space ownership.
enum EgoWorkspaceNavigator {
    @MainActor static func activate() async throws {
        let workspace = NSWorkspace.shared
        guard let url = workspace.urlForApplication(withBundleIdentifier: "com.citrolabs.ego.lite") else {
            throw WorkspaceNavigationError.failed("未找到 ego lite 应用")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        let app = try await workspace.openApplication(at: url, configuration: configuration)
        guard app.isActive, workspace.frontmostApplication?.processIdentifier == app.processIdentifier else {
            throw WorkspaceNavigationError.failed("ego 未成为前台应用，内容已保留")
        }
    }

    /// Observe without activating ego or changing its selected Space/tab.
    @MainActor static func currentWindow() async throws -> (id: Int, title: String) {
        let source = """
        with timeout of 10 seconds
            tell application id "com.citrolabs.ego.lite"
                return {id of front window, title of active tab of front window}
            end tell
        end timeout
        """
        guard let script = NSAppleScript(source: source) else {
            throw WorkspaceNavigationError.failed("无法读取 ego 当前窗口")
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            if (error[NSAppleScript.errorNumber] as? Int) == -1743 {
                throw WorkspaceNavigationError.automationDenied
            }
            throw WorkspaceNavigationError.failed("无法读取 ego 当前窗口：\(error)")
        }
        guard let idText = result.atIndex(1)?.stringValue, let id = Int(idText), id > 0,
              let title = result.atIndex(2)?.stringValue else {
            throw WorkspaceNavigationError.failed("请先在 ego 中打开要使用的空间")
        }
        return (id, title)
    }

    /// Titles only narrow candidates; an exact native/CDP window-ID match authorizes writes.
    static func claimCurrentSpaceScript(windowID: Int, title: String) throws -> String {
        guard windowID > 0, windowID <= Int(Int32.max) else {
            throw WorkspaceNavigationError.failed("无效的 ego 窗口标识")
        }
        let encoded = String(data: try JSONSerialization.data(withJSONObject: [title]), encoding: .utf8)!
        return """
        const spaces = await listTaskSpaces();
        const candidates = spaces.length === 1 ? spaces : spaces.filter(space => space.recentTabTitles?.includes(\(encoded)[0]));
        if (candidates.length !== 1) throw new Error("无法唯一确认 ego 当前空间，请在 ego 中选中一个页面后重试");
        const info = candidates[0];
        if (info.ownership !== "user" && info.taskId) throw new Error("ego 当前空间仍有任务，请先结束该任务后重试");
        const task = await (info.ownership === "user" ? claimTaskSpace : takeOverTaskSpace)(info.id);
        let confirmed = false;
        try {
            const active = (await task.tabs()).find(tab => tab.active);
            if (!active) throw new Error("ego 当前空间没有活动页面");
            const {windowId} = await task.cdp("Browser.getWindowForTarget", {targetId:active.targetId});
            if (windowId !== \(windowID)) throw new Error("ego 当前空间已变化，请重新开始");
            confirmed = true;
            cliLog(JSON.stringify({ok:true, spaceID:task.spaceId}));
        } finally {
            if (!confirmed) await task.finish({keep:"all"});
        }
        """
    }
}
