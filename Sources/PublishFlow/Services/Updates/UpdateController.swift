import AppKit
import Sparkle
import Observation
import OSLog
import PublishKit

/// Sparkle owns networking, archive validation and its independent installer/relauncher.
/// This adapter only translates its official UI callbacks to our presentation model.
@MainActor @Observable
final class UpdateController: NSObject, SPUUserDriver, SPUUpdaterDelegate {
    let state = UpdateModel()
    @ObservationIgnored private var updater: SPUUpdater?
    @ObservationIgnored private var task: DispatchModel?
    @ObservationIgnored private var choice: ((SPUUserUpdateChoice) -> Void)?
    @ObservationIgnored private var install: ((SPUUserUpdateChoice) -> Void)?
    @ObservationIgnored private var cancellation: (() -> Void)?
    @ObservationIgnored private var retryTermination: (() -> Void)?
    @ObservationIgnored private var postponedInstall: (() -> Void)?
    @ObservationIgnored private var observation: NSKeyValueObservation?
    @ObservationIgnored private let logger = Logger(subsystem: "com.publishflow.app", category: "Updates")
    @ObservationIgnored var activate: () -> Void = {}

    var blockingReason: String? { task.flatMap(UpdateSafety.blockingReason) }
    var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发构建" }

    func start(task: DispatchModel) {
        guard self.task == nil else { return }
        self.task = task
        guard Bundle.main.bundleURL.pathExtension == "app",
              let raw = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: raw), url.scheme == "https", url.host != nil,
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32 else {
            state.message = "此构建未配置在线更新，请使用正式应用包。"
            return
        }
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: self)
        self.updater = updater
        do {
            try updater.start()
            state.isConfigured = true
            state.automaticallyChecks = updater.automaticallyChecksForUpdates
            observation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
                Task { @MainActor [weak self] in self?.state.canCheck = change.newValue ?? false }
            }
        } catch {
            fail(error)
        }
    }

    func setAutomaticChecks(_ enabled: Bool) {
        updater?.automaticallyChecksForUpdates = enabled
        state.automaticallyChecks = updater?.automaticallyChecksForUpdates ?? false
    }
    func show() {
        state.isPresented = true
        activate()
        if !state.hasReminder && state.phase != .checking && state.phase != .failed { check() }
    }
    func check() {
        guard let updater, updater.canCheckForUpdates else { return }
        state.message = nil
        updater.checkForUpdates()
    }
    func beginDownload() {
        guard state.phase == .available, !state.informationOnly, let choice else { return }
        guard blockingReason == nil else { state.message = blockingReason; return }
        self.choice = nil
        state.message = nil
        state.installSessionActive = true
        choice(.install)
    }
    func restart() {
        guard blockingReason == nil else { state.message = blockingReason; return }
        state.message = nil
        if let postponedInstall {
            self.postponedInstall = nil
            state.phase = .installing
            postponedInstall()
        } else if let retryTermination {
            self.retryTermination = nil
            state.phase = .installing
            retryTermination()
        } else if let install {
            self.install = nil
            state.phase = .installing
            install(.install)
        }
    }
    func cancel() {
        guard let cancellation else { return }
        self.cancellation = nil
        state.canCancel = false
        cancellation()
    }
    func dismiss() { state.isPresented = false }
    func acknowledge() { state.isPresented = false }

    private func fail(_ error: Error) {
        logger.error("Update failed: \(String(describing: error), privacy: .public)")
        state.phase = .failed
        state.message = (error as NSError).localizedDescription
        state.installSessionActive = false
        state.canCancel = false
        choice = nil; install = nil; cancellation = nil; postponedInstall = nil; retryTermination = nil
    }

    // MARK: Sparkle user-driver contract (all callbacks run on the main thread)
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: state.automaticallyChecks, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
        state.canCancel = true
        state.phase = .checking
        state.isPresented = true
    }
    func showUpdateFound(with appcastItem: SUAppcastItem, state updateState: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        cancellation = nil
        state.canCancel = false
        state.version = appcastItem.displayVersionString
        state.releaseNotes = Self.plainNotes(appcastItem.itemDescription ?? "")
        state.informationOnly = appcastItem.isInformationOnlyUpdate
        state.message = nil
        choice = reply
        if updateState.stage == .installing {
            install = reply
            state.phase = .ready
            state.installSessionActive = true
        } else {
            state.phase = .available
        }
        // A scheduled check only sets a reminder. Never bring the application forward.
        if updateState.userInitiated { state.isPresented = true }
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        guard downloadData.data.count <= 512_000,
              let text = String(data: downloadData.data, encoding: .utf8) else {
            state.releaseNotes = "更新说明不可读取。"
            return
        }
        state.releaseNotes = Self.plainNotes(text)
    }
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
        logger.error("Release notes failed: \(error.localizedDescription, privacy: .public)")
        state.releaseNotes = "暂时无法读取更新说明，可稍后重新检查。"
    }
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        state.phase = .latest
        // Sparkle distinguishes no newer version from incompatible OS/hardware requirements.
        state.message = error.localizedDescription
        state.canCancel = false
        cancellation = nil
        acknowledgement()
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        fail(error)
        acknowledgement()
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
        state.phase = .downloading
        state.installSessionActive = true
        state.canCancel = true
        state.receivedBytes = 0; state.expectedBytes = 0
    }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        state.expectedBytes = expectedContentLength
    }
    func showDownloadDidReceiveData(ofLength length: UInt64) {
        let (value, overflow) = state.receivedBytes.addingReportingOverflow(length)
        state.receivedBytes = overflow ? UInt64.max : value
    }
    func showDownloadDidStartExtractingUpdate() {
        cancellation = nil
        state.canCancel = false
        state.phase = .extracting
        state.extractionProgress = 0
    }
    func showExtractionReceivedProgress(_ progress: Double) {
        state.extractionProgress = progress.isFinite ? min(1, max(0, progress)) : 0
    }
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        install = reply
        state.phase = .ready
        state.message = nil
        state.canCancel = false
        // Wait for an explicit restart click, even if the original download was authorized.
    }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        state.phase = .installing
        if !applicationTerminated { retryTermination = retryTerminatingApplication }
    }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        state.phase = .idle
        state.installSessionActive = false
        state.message = relaunched ? "新版已启动。" : "更新已安装，请重新打开墨驿。"
        acknowledgement()
    }
    func dismissUpdateInstallation() {
        choice = nil; install = nil; cancellation = nil; postponedInstall = nil; retryTermination = nil
        state.canCancel = false
        state.installSessionActive = false
        if ![.failed, .latest].contains(state.phase) { state.phase = .idle }
    }
    func showUpdateInFocus() { state.isPresented = true; activate() }

    // MARK: Last-moment restart safety
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard let reason = blockingReason else { return false }
        postponedInstall = installHandler
        state.phase = .ready
        state.message = reason
        state.isPresented = true
        return true
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let nsError = error as NSError
        if nsError.domain == SUSparkleErrorDomain && nsError.code == SUError.noUpdateError.rawValue { return }
        if nsError.domain == SUSparkleErrorDomain && nsError.code == SUError.installationCanceledError.rawValue { return }
        fail(error)
    }

    /// Release notes are rendered as inert text, never as executable remote HTML.
    static func plainNotes(_ text: String) -> String {
        let limited = String(text.prefix(100_000))
        return limited.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
