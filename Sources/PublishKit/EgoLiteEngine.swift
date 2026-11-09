import Foundation

/// 步骤执行结果：取适配器脚本输出的最后一行 JSON（cliLog 产物）。
public struct StepResult {
    public let rawOutput: String
    public init(rawOutput: String, json: [String: Any]?) { self.rawOutput = rawOutput; self.json = json }
    public let json: [String: Any]?

    public func string(_ key: String) -> String? { json?[key] as? String }
    public func bool(_ key: String) -> Bool? { json?[key] as? Bool }
}

/// EgoLiteEngine —— 有意保持极简。
///
/// 只依赖官方调用规范（lite.ego.app/docs/ego-browser）：
///   `ego-browser nodejs < script`   —— stdin 喂一段 Node 脚本，脚本用官方 helper 操作浏览器。
///
/// 每次调用启动一个子进程，执行一段脚本并读取结果 JSON。
/// 生产渠道通过 EgoBridge 调用 runRaw；恢复由任务服务与渠道适配器协调。
public struct EgoLiteEngine {
    public let binaryPath: String

    public enum EngineError: LocalizedError {
        case binaryNotFound
        case timeout
        case failed(exitCode: Int32, tail: String)

        public var errorDescription: String? {
            switch self {
            case .binaryNotFound:
                return "未找到 ego-browser 命令。请安装 ego lite 并完成首次引导（官网 lite.ego.app）。"
            case .timeout:
                return "执行超时"
            case .failed(let code, let tail):
                return "适配器执行失败（exit=\(code)）：\n" + tail
            }
        }
    }

    public init(binaryPath: String? = nil) throws {
        if let binaryPath {
            self.binaryPath = binaryPath
        } else if let found = (try? Shell.capture("/usr/bin/which", ["ego-browser"]))?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !found.isEmpty, FileManager.default.isExecutableFile(atPath: found) {
            self.binaryPath = found
        } else {
            throw EngineError.binaryNotFound
        }
    }

    // MARK: - CLI 模拟流程

    /// 填充：打开目标平台编辑页，填入内容，停在可编辑草稿。
    /// 返回的 JSON 里约定含 `phase`（awaitingConfirm / failed）与 `message`。
    @discardableResult
    public func prepare(adapterPath: String, task: PublishTask, timeout: TimeInterval = 300) async throws -> StepResult {
        try await run(adapter: adapterPath, task: task, step: "prepare", timeout: timeout)
    }

    /// 回读：用户在 ego 浏览器里人工发布后，读取发布结果（链接）。
    @discardableResult
    public func finalize(adapterPath: String, task: PublishTask, timeout: TimeInterval = 120) async throws -> StepResult {
        try await run(adapter: adapterPath, task: task, step: "finalize", timeout: timeout)
    }

    // MARK: - 官方规范的唯一调用姿势

    /// 脚本模板：官方规定「单脚本自包含」。任务 JSON 直接内嵌为常量，无文件、无环境变量依赖。
    public static func taskScript(adapterPath: String, task: PublishTask, step: String) -> String {
        let taskJSON = String(data: try! JSONEncoder.encoderWithDates.encode(task), encoding: .utf8) ?? "{}"
        return """
        const mod = await import("\(adapterPath)");
        const result = await mod.run(JSON.parse('\(taskJSON.escapingSingleQuotes())'), "\(step)");
        cliLog(JSON.stringify(result));
        """
    }

    @discardableResult
    public func run(adapter: String, task: PublishTask, step: String, timeout: TimeInterval) async throws -> StepResult {
        let script = Self.taskScript(adapterPath: adapter, task: task, step: step)
        return try await executeAndCollect(script: script, timeout: timeout)
    }

    /// 运行任意官方规范脚本（调试/清理用）
    @discardableResult
    public func runRaw(script: String, timeout: TimeInterval = 60) async throws -> StepResult {
        try await executeAndCollect(script: script, timeout: timeout)
    }

    private func executeAndCollect(script: String, timeout: TimeInterval) async throws -> StepResult {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = ["nodejs"]

        let stdin = Pipe()
        let stdout = Pipe(), stderr = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        let outBuf = DataBuffer(), errBuf = DataBuffer()
        stdout.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil } else { outBuf.append(d) }
        }
        stderr.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil } else { errBuf.append(d) }
        }

        defer {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            try? stdin.fileHandleForWriting.close()
        }
        let exitCode: Int32 = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try proc.run()
            if Task.isCancelled { proc.terminate() }
            do {
                try Task.checkCancellation()
                try stdin.fileHandleForWriting.write(contentsOf: Data(script.utf8))
                try stdin.fileHandleForWriting.close()
            } catch {
                if proc.isRunning { proc.terminate() }
                throw error
            }
            let killer = Task {
                do { try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000)) }
                catch { return }
                if proc.isRunning { proc.terminate() }
            }
            defer { killer.cancel() }
            let status: Int32 = await withCheckedContinuation { cont in
                proc.terminationHandler = { p in cont.resume(returning: p.terminationStatus) }
            }
            try Task.checkCancellation()
            return status
        } onCancel: {
            if proc.isRunning { proc.terminate() }
        }

        // 给 readability handler 一点时间收尾
        try await Task.sleep(nanoseconds: 200_000_000)
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil

        let outText = String(data: outBuf.data, encoding: .utf8) ?? ""
        let errText = String(data: errBuf.data, encoding: .utf8) ?? ""

        // 结果 = 输出流里最后一行可解析的 JSON（cliLog 可能走 stdout 或 stderr，都扫）
        let combined = outText + "\n" + errText
        let lines = combined.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let candidate = lines.reversed().first { $0.hasPrefix("{") }
        let parsed: [String: Any]? = candidate.flatMap {
            ($0.data(using: .utf8)).flatMap { try? JSONSerialization.jsonObject(with: $0) }
        } as? [String: Any]
        guard exitCode == 0 else {
            throw EngineError.failed(exitCode: exitCode, tail: lines.suffix(12).joined(separator: "\n"))
        }
        if let obj = parsed {
            return StepResult(rawOutput: combined, json: obj)
        }

        if exitCode == 0 {
            return StepResult(rawOutput: combined, json: nil) // 无结果但正常退出
        }
        let tail = lines.suffix(12).joined(separator: "\n")
        throw EngineError.failed(exitCode: exitCode, tail: tail)
    }
}

extension String {
    /// JSON 文本安全地嵌入 JS 单引号字符串字面量
    func escapingSingleQuotes() -> String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}

/// 线程安全输出缓冲（readabilityHandler 在后台队列回调）
final class DataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()
    var data: Data {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
    func append(_ d: Data) {
        lock.lock(); defer { lock.unlock() }
        storage.append(d)
    }
}

// MARK: - Shell 辅助

enum Shell {
    @discardableResult
    static func capture(_ launchPath: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
