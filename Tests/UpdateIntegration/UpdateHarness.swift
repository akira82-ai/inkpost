// Isolated end-to-end fixture. Never uses the production app's identity or lock.
import AppKit
import Sparkle
import PublishKit

@main @MainActor
final class UpdateHarness: NSObject, NSApplicationDelegate {
    private let driver = UpdateController()
    private var updater: SPUUpdater!
    private var lock: ApplicationInstanceLock!
    private var timer: Timer?
    private var previousPhase = ""
    private let started = Date()
    private var waitingSince: Date?
    private var root: URL { URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "UpdateTestRoot") as! String) }

    private func log(_ line: String) {
        let url = root.appending(path: "events.txt")
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        let file = try! FileHandle(forWritingTo: url)
        file.seekToEndOfFile()
        file.write(Data((line + "\n").utf8))
        try! file.close()
    }
    static func main() {
        let app = NSApplication.shared, delegate = UpdateHarness()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            lock = try ApplicationInstanceLock(directory: root.appending(path: "lock"))
            guard try lock.acquire() else { log("DUPLICATE"); NSApp.terminate(nil); return }
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
            log("START \(version) PID \(getpid())")
            if version == "2.0" { log("SUCCESS NEW VERSION SINGLE OWNER"); NSApp.terminate(nil); return }
            // Only this fixture permits loopback HTTP. Production start() requires HTTPS.
            updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: driver)
            try updater.start()
            if root.lastPathComponent == "valid" { updater.checkForUpdatesInBackground() }
            else { updater.checkForUpdates() }
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        } catch { log("ERROR \(error)"); NSApp.terminate(nil) }
    }
    private func tick() {
        let phase = driver.state.phase
        if Date().timeIntervalSince(started) > 45 { log("ERROR TIMEOUT"); NSApp.terminate(nil); return }
        if "\(phase)" != previousPhase {
            previousPhase = "\(phase)"
            log("PHASE \(phase) \(driver.state.message ?? "")")
        }
        if phase == .available {
            if root.lastPathComponent == "valid" && driver.state.isPresented {
                log("ERROR BACKGROUND CHECK OPENED PANEL"); NSApp.terminate(nil); return
            }
            // Leave the candidate alone first: discovery must never start a download.
            guard let waitingSince else { self.waitingSince = Date(); log("WAITING FOR EXPLICIT DOWNLOAD"); return }
            if Date().timeIntervalSince(waitingSince) > 0.5 { driver.beginDownload() }
        }
        if phase == .ready { driver.restart() }
        if phase == .failed || phase == .latest { NSApp.terminate(nil) }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        log("TERMINATE")
        return .terminateNow
    }
}
