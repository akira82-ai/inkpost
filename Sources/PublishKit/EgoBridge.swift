import Foundation

/// EgoBridge —— 确定性渠道适配器的浏览器工具层。
///
/// 每个工具调用 = 一次 ego-browser 官方调用（spawn → 执行 helper → 退出读 JSON）。
/// 无协议、无长驻进程、无流式问题；TaskSpace 按名字跨调用恢复浏览器状态。
/// 可通过注入传输独立测试。
public struct EgoBridge {
    let engine: EgoLiteEngine
    public let spaceName: String
    public let pageLabel: String

    public init(spaceName: String, engine: EgoLiteEngine, pageLabel: String = "p1") throws {
        self.spaceName = spaceName
        self.engine = engine
        self.pageLabel = pageLabel
    }

    // MARK: - 工具集（映射到官方 helper）

    /// 打开/复用页面并确认加载完成
    public func navigate(url: String) async throws -> String {
        let r = try await run(
            """
            await page.goto(\(jsStr(url)));
            const info = await page.info();
            cliLog(JSON.stringify({ ok: true, url: info.url, title: info.title }));
            """)
        return r
    }

    /// 语义快照：返回 [ref=N, loc=...] 树
    public func snapshot(scope: String = "full_page") async throws -> String {
        let r = try await run(
            """
            const snap = await page.snapshot({ scope: \(jsStr(scope)) });
            cliLog(JSON.stringify({ ok: true, snapshot: snap }));
            """)
        return r
    }

    /// 填充输入框（ref 或 CSS selector）
    public func fill(target: String, text: String) async throws -> String {
        let r = try await run(
            """
            await page.fill(\(jsStr(target)), \(jsStr(text)));
            cliLog(JSON.stringify({ ok: true }));
            """)
        return r
    }

    /// 上传本地文件到 input[type=file]
    public func upload(target: String, paths: [String]) async throws -> String {
        let r = try await run(
            """
            await page.setInputFiles(\(jsStr(target)), \(jsArr(paths)));
            cliLog(JSON.stringify({ ok: true, count: \(paths.count) }));
            """)
        return r
    }

    /// 内部点击辅助。
    public func click(target: String, label: String) async throws -> String {
        let r = try await run(
            """
            await page.click(\(jsStr(target)), { label: \(jsStr(label)) });
            cliLog(JSON.stringify({ ok: true }));
            """)
        return r
    }

    /// 内部页面求值，仅供可信实现与 fixture 使用。
    public func evaluate(js source: String) async throws -> String {
        let r = try await run(
            """
            const v = await page.evaluate(\(jsStr(source)));
            cliLog(JSON.stringify({ ok: true, value: v }));
            """)
        return r
    }

    /// Read-only element inspection.
    public func inspect(target: String) async throws -> String {
        let source = "(() => { const el = document.querySelector(\(jsStr(target))); if (!el) throw new Error('element not found'); return {text: el.value ?? el.innerText ?? el.textContent ?? '', files: el.files ? el.files.length : 0, images: el.querySelectorAll('img').length}; })()"
        return try await evaluate(js: source)
    }

    // MARK: - 执行内核

    /// 把一段官方 helper 调用包进"Space 恢复 + 单脚本执行 + 结果提取"
    func run(_ body: String) async throws -> String {
        let script = """
        const task = await taskSpace(\(jsStr(spaceName)));
        const page = task.page(\(jsStr(pageLabel)));
        try {
          \(body)
        } catch (e) {
          cliLog(JSON.stringify({ ok: false, error: String(e && e.message || e) }));
        }
        """
        let result = try await engine.runRaw(script: script, timeout: 120)
        // EgoLiteEngine 已提取最后一行 JSON；此处还原为字符串供适配器读取
        if let json = result.json {
            if let err = json["error"] as? String {
                throw BridgeError.toolFailed(err)
            }
            return pretty(json)
        }
        throw BridgeError.noResult(String(result.rawOutput.suffix(400)))
    }

    public enum BridgeError: LocalizedError {
        case toolFailed(String)
        case noResult(String)
        public var errorDescription: String? {
            switch self {
            case .toolFailed(let m): return "工具执行失败：\(m)"
            case .noResult(let tail): return "工具无结果输出：\(tail)"
            }
        }
    }

    func pretty(_ obj: [String: Any]) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
              let s = String(data: d, encoding: .utf8) else { return "\(obj)" }
        return s
    }

    func jsStr(_ s: String) -> String {
        // 生成 JS 字符串字面量（手工转义，避免 JSONSerialization 把顶层字符串包进数组）
        let escaped = s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    func jsArr(_ a: [String]) -> String {
        let d = try? JSONSerialization.data(withJSONObject: a)
        return d.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }
}
