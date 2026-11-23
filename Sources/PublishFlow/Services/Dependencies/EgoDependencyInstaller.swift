import Foundation

/// Uses the same distribution URLs as the official ego-browser macOS installer.
/// Existing installations are never replaced; Gatekeeper and publisher identity are verified.
enum EgoDependencyInstaller {
    static let bundleID = "com.citrolabs.ego.lite"
    static let publisherTeam = "JGQLC6YQYJ"

    static var packageURL: URL {
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x64"
        #endif
        return URL(string: "https://cdn.ego.app/setup/macos/\(architecture)/egolite-fHoqgZ74bOEM.dmg")!
    }

    static func install() async throws -> URL {
        let (download, response) = try await URLSession.shared.download(from: packageURL)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url?.scheme == "https", response.url?.host == "cdn.ego.app" else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return try await Task.detached(priority: .userInitiated) {
            let files = FileManager.default
            let directory = files.temporaryDirectory.appendingPathComponent("inkpost-ego-\(UUID().uuidString)")
            try files.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? files.removeItem(at: directory) }
            let image = directory.appendingPathComponent("ego.dmg")
            try files.moveItem(at: download, to: image)
            let mount = directory.appendingPathComponent("volume")
            try run("/usr/bin/hdiutil", ["attach", image.path, "-readonly", "-nobrowse", "-mountpoint", mount.path])
            defer { try? run("/usr/bin/hdiutil", ["detach", mount.path]) }
            let source = mount.appendingPathComponent("ego lite.app")
            guard Bundle(url: source)?.bundleIdentifier == bundleID else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try verify(source)
            let applications = files.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
            try files.createDirectory(at: applications, withIntermediateDirectories: true)
            let destination = applications.appendingPathComponent("ego lite.app")
            let staging = applications.appendingPathComponent(".inkpost-ego-\(UUID().uuidString)")
            try files.createDirectory(at: staging, withIntermediateDirectories: false)
            defer { try? files.removeItem(at: staging) }
            let stagedApp = staging.appendingPathComponent("ego lite.app")
            try files.copyItem(at: source, to: stagedApp)
            try verify(stagedApp)
            // Same-volume rename installs only the verified complete bundle, never overwriting an existing app.
            try files.moveItem(at: stagedApp, to: destination)
            return destination
        }.value
    }

    private static func verify(_ app: URL) throws {
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-R",
            "anchor apple generic and certificate leaf[subject.OU] = \"\(publisherTeam)\"", app.path])
        try run("/usr/sbin/spctl", ["--assess", "--type", "execute", app.path])
    }

    private static func run(_ binary: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        // A temporary file avoids pipe-buffer deadlocks while preserving actionable failures.
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("inkpost-install-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: output) }
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        let deadline = Date().addingTimeInterval(120)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        if process.isRunning {
            process.terminate()
            throw NSError(domain: "Inkpost.EgoInstall", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "安装步骤超时，请重试"])
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = (try? String(contentsOf: output, encoding: .utf8)) ?? "安装命令失败"
            throw NSError(domain: "Inkpost.EgoInstall", code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: String(detail.suffix(1500))])
        }
    }
}
