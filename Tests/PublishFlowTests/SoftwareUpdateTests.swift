import AppKit
import SwiftUI
import Testing
import PublishKit
import Sparkle
@testable import PublishFlow

@MainActor
struct SoftwareUpdateTests {
    @Test func titlebarReminderWorksWithoutSettingsButton() async throws {
        _ = NSApplication.shared
        let updates = UpdateController()
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 420, height: 540),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        let bar = NativeMenuBar(controller: DispatchController(service: DispatchService(), settings: DispatchSettings()),
                                presentation: TaskPresentation(), openSettings: {}, window: window, updates: updates)
        defer { bar.stop() }
        let controls = try #require(window.titlebarAccessoryViewControllers.first?.view as? UpdateTitlebarControls)
        window.contentView?.superview?.layoutSubtreeIfNeeded()
        #expect(controls.frame.width == 0 && controls.reminder.isHidden)
        for (phase, label) in [(UpdatePhase.available, "有更新"), (.downloading, "下载中 35%"),
                               (.ready, "查看更新"), (.idle, "")] {
            updates.state.expectedBytes = 100
            updates.state.receivedBytes = 35
            updates.state.phase = phase
            try await Task.sleep(for: .milliseconds(50))
            window.contentView?.superview?.layoutSubtreeIfNeeded()
            if label.isEmpty {
                #expect(controls.frame.width == 0 && controls.reminder.isHidden)
            } else {
                #expect(controls.reminder.accessibilityLabel() == label)
                #expect(controls.frame.width == controls.reminder.frame.width)
            }
        }
        #expect(window.titlebarAccessoryViewControllers.count == 1)
    }

    @Test func contextMenuReflectsUpdateStateAndReleasesStatusItem() {
        _ = NSApplication.shared
        let updates = UpdateController()
        updates.state.isConfigured = true
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 540),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let bar = NativeMenuBar(controller: DispatchController(service: DispatchService(), settings: DispatchSettings()),
                                presentation: TaskPresentation(), openSettings: {}, window: window, updates: updates)
        defer { bar.stop() }
        for (phase, title, enabled) in [(UpdatePhase.idle, "检查更新…", true),
            (.checking, "正在检查更新…", false), (.downloading, "正在下载更新…", false),
            (.extracting, "正在准备更新…", false), (.ready, "重启并使用新版…", true),
            (.installing, "正在安装并重启…", false), (.failed, "查看更新问题…", true)] {
            updates.state.phase = phase
            bar.menuWillOpen(bar.contextMenu)
            #expect(bar.contextMenu.item(at: 2)?.title == title)
            #expect(bar.contextMenu.item(at: 2)?.isEnabled == enabled)
        }
        bar.item.menu = bar.contextMenu
        bar.menuDidClose(bar.contextMenu)
        #expect(bar.item.menu == nil)
    }

    @Test func everyInMemoryContentAndTaskStateBlocksRestart() {
        let task = DispatchModel()
        #expect(UpdateSafety.blockingReason(task) == nil)
        for phase in [TargetPhase.preparing, .needLogin, .awaitingConfirm, .failed, .cancelled] {
            task.overallPhase = phase
            #expect(UpdateSafety.blockingReason(task) != nil)
        }
        task.overallPhase = .pending
        task.title = " "
        #expect(UpdateSafety.blockingReason(task) != nil)
        task.title = ""; task.markdown = "\n"
        #expect(UpdateSafety.blockingReason(task) != nil)
        task.markdown = ""; task.assetPaths = ["image.png"]
        #expect(UpdateSafety.blockingReason(task) != nil)
        task.assetPaths = []; task.isHandingOff = true
        #expect(UpdateSafety.blockingReason(task) != nil)
        task.isHandingOff = false; task.isSettling = true
        #expect(UpdateSafety.blockingReason(task) != nil)
    }

    @Test func downloadIsNeverImplicitAndCancelRunsOnce() {
        let updates = UpdateController()
        var cancellations = 0
        updates.showDownloadInitiated { cancellations += 1 }
        updates.showDownloadDidReceiveExpectedContentLength(100)
        updates.showDownloadDidReceiveData(ofLength: 30)
        #expect(updates.state.progress == 0.3)
        updates.dismiss()
        #expect(!updates.state.isPresented)
        #expect(updates.state.phase == .downloading)
        #expect(cancellations == 0)
        updates.cancel(); updates.cancel()
        #expect(cancellations == 1)
        updates.dismissUpdateInstallation()
        #expect(!updates.state.installSessionActive && !updates.state.canCancel)
    }

    @Test func readyUpdateRequiresExplicitRestartAndRechecksNewDraft() {
        let updates = UpdateController(), task = DispatchModel()
        updates.start(task: task) // Test runner has no configured app bundle; safety still binds.
        var replies: [SPUUserUpdateChoice] = []
        updates.showDownloadInitiated {}
        updates.showDownloadDidStartExtractingUpdate()
        updates.showReady(toInstallAndRelaunch: { replies.append($0) })
        #expect(updates.state.phase == .ready)
        #expect(replies.isEmpty)
        updates.dismiss()
        #expect(replies.isEmpty)
        task.markdown = "new content"
        updates.restart()
        #expect(replies.isEmpty)
        #expect(updates.state.message != nil)
        task.markdown = ""
        updates.restart(); updates.restart()
        #expect(replies.count == 1 && replies.first == .install)
    }

    @Test func failuresRemainVisibleAndNeverReportSuccess() {
        let updates = UpdateController()
        var acknowledged = false
        updates.showDownloadInitiated {}
        updates.showUpdaterError(NSError(domain: "test", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Invalid signature"]), acknowledgement: { acknowledged = true })
        #expect(acknowledged)
        #expect(updates.state.phase == .failed)
        #expect(updates.state.message == "Invalid signature")
        updates.dismissUpdateInstallation()
        #expect(updates.state.phase == .failed)
        #expect(!updates.state.installSessionActive)
    }

    @Test func restartWaitsForSheetDismissalAndRunsOnce() {
        let updates = UpdateController()
        var installs = 0
        updates.showReady(toInstallAndRelaunch: { _ in installs += 1 })
        updates.state.isPresented = true
        updates.restart(); updates.restart()
        #expect(!updates.state.isPresented && installs == 0)
        #expect(!updates.canRestart)
        updates.presentationDidDismiss(); updates.presentationDidDismiss()
        #expect(installs == 1 && updates.state.phase == .installing)
        #expect(!updates.canRestart)
    }

    @Test func dismissalRechecksDraftAndInstallerFailureCancelsPendingRestart() {
        let updates = UpdateController(), task = DispatchModel()
        updates.start(task: task)
        var installs = 0
        updates.showReady(toInstallAndRelaunch: { _ in installs += 1 })
        updates.state.isPresented = true
        updates.restart()
        task.markdown = "new draft during dismissal"
        updates.presentationDidDismiss()
        #expect(installs == 0 && updates.state.isPresented)
        #expect(updates.state.message != nil && task.markdown == "new draft during dismissal")
        task.markdown = ""
        updates.restart()
        updates.showUpdaterError(NSError(domain: "test", code: 2), acknowledgement: {})
        updates.presentationDidDismiss()
        #expect(installs == 0 && updates.state.phase == .failed)
    }

    @Test func swiftUIDismissalMustAlsoWaitForNativeSheetDetachment() async throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 420, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                             styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        sheet.isReleasedWhenClosed = false
        defer { window.orderOut(nil); sheet.orderOut(nil) }
        window.orderFront(nil)
        window.beginSheet(sheet, completionHandler: { _ in })
        let updates = UpdateController()
        var installs = 0
        updates.showReady(toInstallAndRelaunch: { _ in
            #expect(window.attachedSheet == nil)
            installs += 1
        })
        updates.state.isPresented = true
        updates.restart()
        updates.presentationDidDismiss()
        #expect(installs == 0)
        window.endSheet(sheet)
        for _ in 0..<100 where installs == 0 { try await Task.sleep(for: .milliseconds(20)) }
        #expect(installs == 1)
    }

    @Test func retryQuitAlsoWaitsForSheetAndOrdinaryDismissNeverInstalls() {
        let updates = UpdateController()
        var quits = 0
        updates.showInstallingUpdate(withApplicationTerminated: false, retryTerminatingApplication: { quits += 1 })
        updates.state.isPresented = true
        updates.dismiss(); updates.presentationDidDismiss()
        #expect(quits == 0)
        updates.state.isPresented = true
        updates.restart()
        #expect(quits == 0)
        updates.presentationDidDismiss()
        #expect(quits == 1)
        updates.showInstallingUpdate(withApplicationTerminated: true, retryTerminatingApplication: { quits += 1 })
        #expect(!updates.canRestart)
        updates.restart()
        #expect(quits == 1)
    }

    @Test func noUpdateIsNotTurnedIntoGenericFailure() {
        let updates = UpdateController()
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: updates, delegate: updates)
        let error = NSError(domain: SUSparkleErrorDomain, code: Int(SUError.noUpdateError.rawValue),
                            userInfo: [NSLocalizedDescriptionKey: "No compatible update"])
        updates.showUpdateNotFoundWithError(error, acknowledgement: {})
        updates.updater(updater, didAbortWithError: error)
        updates.dismissUpdateInstallation()
        #expect(updates.state.phase == .latest)
        #expect(updates.state.message == "No compatible update")
    }

    @Test func terminationProtectsDraftWhileInstallerIsPending() {
        let updates = UpdateController(), task = DispatchModel()
        updates.start(task: task)
        let lifecycle = AppLifecycle()
        lifecycle.configureUpdates(updates)
        updates.showDownloadInitiated {}
        task.markdown = "not saved"
        #expect(lifecycle.applicationShouldTerminate(NSApplication.shared) == .terminateCancel)
        #expect(task.markdown == "not saved")
        task.markdown = ""
        #expect(lifecycle.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
    }

    @Test func updaterViewFitsMainWindowAndNotesAreInert() {
        _ = NSApplication.shared
        let updates = UpdateController()
        for phase in [UpdatePhase.available, .downloading, .extracting, .ready, .failed, .latest] {
            updates.state.phase = phase
            updates.state.version = "0.17.0"
            updates.state.releaseNotes = String(repeating: "Update notes\n", count: 100)
            let view = NSHostingView(rootView: SoftwareUpdateView(controller: updates, model: updates.state))
            #expect(view.fittingSize.width <= 420)
            #expect(view.fittingSize.height < 650)
        }
        #expect(UpdateController.plainNotes("<script>window.test=1</script><b>Fix</b>") == "window.test=1Fix")
    }
}
