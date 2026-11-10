import Foundation
import AppKit
import Testing
import PublishKit
@testable import PublishFlow

@MainActor
struct ApplicationInstanceTests {
    // App startup is a top-level main-run-loop call, not a nested DispatchQueue.main task.
    // The latter cannot reenter its own dispatch source to deliver distributed notifications.
    private func launch(_ instance: ApplicationInstance, request: ApplicationInstance.Request = .activate) async throws -> ApplicationInstance.Outcome {
        try await withCheckedThrowingContinuation { continuation in
            RunLoop.main.perform(inModes: [.default]) {
                MainActor.assumeIsolated {
                    do { continuation.resume(returning: try instance.start(request: request, timeout: 2)) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        }
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "inkpost-instance-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func independentOpensExcludeEachOtherAndStaleMetadataDoesNotBlockRestart() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var first: ApplicationInstanceLock? = try ApplicationInstanceLock(directory: directory)
        let second = try ApplicationInstanceLock(directory: directory)
        #expect(try first?.acquire() == true)
        #expect(try !second.acquire())
        let previous = try #require(first?.owner)
        #expect(try second.readOwner() == previous)
        first = nil
        #expect(try second.acquire())
        #expect(try second.readOwner() == second.owner)
        #expect(second.owner.token != previous.token)
    }

    @Test func childProcessCrashReleasesKernelLockWithoutDeletingFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let contender = try ApplicationInstanceLock(directory: directory)
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", "import os,fcntl,signal,sys; fd=os.open(sys.argv[1],os.O_RDWR); fcntl.flock(fd,fcntl.LOCK_EX); print('locked',flush=True); signal.pause()",
                             directory.appending(path: "instance.lock").path]
        process.standardOutput = output
        try process.run()
        defer { if process.isRunning { process.terminate(); process.waitUntilExit() } }
        #expect(String(data: output.fileHandleForReading.availableData, encoding: .utf8) == "locked\n")
        #expect(try !contender.acquire())
        process.terminate()
        process.waitUntilExit()
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "instance.lock").path))
        #expect(try contender.acquire())
    }

    @Test func duplicateRequiresAcknowledgedActivationAndDoesNotConstructAnotherOwner() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = try ApplicationInstance(directory: directory)
        #expect(try owner.start() == .primary)
        defer { owner.stopListening() }
        _ = NSApplication.shared
        let controller = DispatchController(service: DispatchService(), settings: DispatchSettings())
        let state = controller.state
        state.title = "Original title"
        state.markdown = " raw\n\ncontent 🖋️ "
        state.assetPaths = ["/tmp/first.png", "/tmp/second.png"]
        state.selectedPlatforms = [.jike, .x]
        state.taskID = UUID()
        state.overallPhase = .needLogin
        let taskID = state.taskID
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let presentation = TaskPresentation()
        let bar = NativeMenuBar(controller: controller, presentation: presentation, openSettings: {}, window: window)
        defer { bar.stop() }
        var activations = 0
        var stops = 0
        owner.whenReady(activate: {
            activations += 1
            bar.showMainWindow()
            return window.isVisible
        }, stop: { stops += 1 })
        for _ in 0..<3 {
            let duplicate = try ApplicationInstance(directory: directory)
            #expect(try await launch(duplicate) == .activatedExisting)
        }
        #expect(activations == 3)
        #expect(stops == 0)
        #expect(bar.mainWindow === window)
        #expect(window.isVisible)
        #expect(state.title == "Original title")
        #expect(state.markdown == " raw\n\ncontent 🖋️ ")
        #expect(state.assetPaths == ["/tmp/first.png", "/tmp/second.png"])
        #expect(state.selectedPlatforms == [.jike, .x])
        #expect(state.taskID == taskID)
        #expect(state.overallPhase == .needLogin)
    }

    @Test func activationDuringStartupWaitsForWindowReadiness() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = try ApplicationInstance(directory: directory)
        #expect(try owner.start() == .primary)
        defer { owner.stopListening() }
        var activations = 0
        let timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { _ in
            MainActor.assumeIsolated { owner.whenReady(activate: { activations += 1; return true }, stop: {}) }
        }
        defer { timer.invalidate() }
        let duplicate = try ApplicationInstance(directory: directory)
        #expect(try await launch(duplicate) == .activatedExisting)
        #expect(activations == 1)
    }

    @Test func unresponsiveOwnerTimesOutWithoutTakingOverOrStoppingIt() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = try ApplicationInstanceLock(directory: directory)
        #expect(try owner.acquire())
        let duplicate = try ApplicationInstance(directory: directory)
        #expect(throws: (any Error).self) { try duplicate.start(timeout: 0.2) }
        #expect(owner.isOwner)
        let contender = try ApplicationInstanceLock(directory: directory)
        #expect(try !contender.acquire())
    }

    @Test func failedWindowActivationCannotAcknowledgeSuccessfulHandoff() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = try ApplicationInstance(directory: directory)
        #expect(try owner.start() == .primary)
        defer { owner.stopListening() }
        owner.whenReady(activate: { false }, stop: {})
        let duplicate = try ApplicationInstance(directory: directory)
        await #expect(throws: (any Error).self) { try await launch(duplicate) }
    }

    @Test func stopModeExitsWhenNoInstanceAndWaitsForActualOwnerExit() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let stopper = try ApplicationInstance(directory: directory)
            #expect(try stopper.start(request: .stop) == .stopped)
        }
        var owner: ApplicationInstance? = try ApplicationInstance(directory: directory)
        #expect(try owner?.start() == .primary)
        var stopped = false
        owner?.whenReady(activate: { true }, stop: {
            stopped = true
            owner?.stopListening()
            owner = nil
        })
        let stopper = try ApplicationInstance(directory: directory)
        #expect(try await launch(stopper, request: .stop) == .stopped)
        #expect(stopped)
        #expect(owner == nil)
    }
}
