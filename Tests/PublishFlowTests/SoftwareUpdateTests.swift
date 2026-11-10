import AppKit
import SwiftUI
import Testing
import PublishKit
import Sparkle
@testable import PublishFlow

@MainActor
struct SoftwareUpdateTests {
    @Test func titlebarReminderExpandsLeftWithoutMovingGear() async throws {
        _ = NSApplication.shared
        let updates = UpdateController()
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 420, height: 540),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        let bar = NativeMenuBar(controller: DispatchController(service: DispatchService(), settings: DispatchSettings()),
                                presentation: TaskPresentation(), openSettings: {}, window: window, updates: updates)
        defer { bar.stop() }
        let controls = try #require(window.titlebarAccessoryViewControllers.first?.view as? UpdateTitlebarControls)
        window.contentView?.superview?.layoutSubtreeIfNeeded()
        let originalX = controls.gear.convert(controls.gear.bounds, to: nil).midX
        #expect(controls.frame.width == 36 && controls.reminder.isHidden)
        for (phase, label) in [(UpdatePhase.available, "有更新"), (.downloading, "下载中 35%"),
                               (.ready, "查看更新"), (.idle, "")] {
            updates.state.expectedBytes = 100
            updates.state.receivedBytes = 35
            updates.state.phase = phase
            try await Task.sleep(for: .milliseconds(50))
            window.contentView?.superview?.layoutSubtreeIfNeeded()
            let gearX = controls.gear.convert(controls.gear.bounds, to: nil).midX
            #expect(abs(gearX - originalX) < 0.5)
            if label.isEmpty {
                #expect(controls.frame.width == 36 && controls.reminder.isHidden)
            } else {
                #expect(controls.reminder.accessibilityLabel() == label)
                #expect(controls.reminder.frame.maxX < controls.gear.frame.minX)
            }
        }
        #expect(window.titlebarAccessoryViewControllers.count == 1)
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
