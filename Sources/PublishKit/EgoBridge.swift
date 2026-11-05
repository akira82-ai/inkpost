import Foundation

/// EgoBridge —— App 内置极简 agent 的「工具层」。
///
/// 每个工具调用 = 一次 ego-browser 官方调用（spawn → 执行 helper → 退出读 JSON）。
/// 无协议、无长驻进程、无流式问题；TaskSpace 按名字跨调用恢复浏览器状态。
/// 可脱离 LLM 独立测试（确定性）。
public struct EgoBridge {
    let engine: EgoLiteEngine
    public let spaceName: String

    public init(spaceName: String, engine: EgoLiteEngine) throws {
        self.spaceName = spaceName
        self.engine = engine
    }

    // MARK: - 工具集（映射到官方 helper）

    /// 打开/复用页面并确认加载完成
    public func navigate(url: String) async throws -> String {
        let r = try await run(
            """
            await ensureRealTab();
            await openOrReuseTab(\(jsStr(url)), { wait: true, timeout: 30 });
            const info = await pageInfo();
            cliLog(JSON.stringify({ ok: true, url: info.url, title: info.title }));
            """)
        return r
    }

    /// 语义快照（LLM 的眼睛）：返回 [ref=N, loc=...] 树
    public func snapshot(scope: String = "full_page") async throws -> String {
        let r = try await run(
            """
            const snap = await snapshotText({ scope: \(jsStr(scope)) });
            cliLog(JSON.stringify({ ok: true, snapshot: snap }));
            """)
        return r
    }

    /// 填充输入框（ref 或 CSS selector）
    public func fill(target: String, text: String) async throws -> String {
        let r = try await run(
            """
            await fillInput(\(jsStr(target)), \(jsStr(text)));
            cliLog(JSON.stringify({ ok: true }));
            """)
        return r
    }

    /// 向 contenteditable 富文本编辑器注入 HTML（编辑器自身管线消化插入内容）
    public func pasteHTML(target: String, html: String, plainFallback: String) async throws -> String {
        // 以拼接方式生成 js() 源码；HTML 经 JSON 字符串字面量嵌入，天然转义安全
        let source =
            "(() => {" +
            "  const sel = \(jsStr(target));" +
            "  const el = (document.activeElement && document.activeElement.isContentEditable)" +
            "    ? document.activeElement : document.querySelector(sel);" +
            "  if (!el) throw new Error('editor not found');" +
            "  el.focus();" +
            "  document.execCommand('insertHTML', false, \(jsStr(html)));" +
            "  el.dispatchEvent(new Event('input', { bubbles: true }));" +
            "  return el.textContent.length;" +
            "})()"
        let r = try await run(
            """
            await click(\(jsStr(target)), { label: '聚焦编辑器' });
            const len = await js(\(jsStr(source)));
            cliLog(JSON.stringify({ ok: true, textLength: len }));
            """)
        _ = plainFallback
        return r
    }

    /// 上传本地文件到 input[type=file]
    public func upload(target: String, paths: [String]) async throws -> String {
        let r = try await run(
            """
            for (const p of \(jsArr(paths))) {
              await uploadFile(\(jsStr(target)), p);
            }
            cliLog(JSON.stringify({ ok: true, count: \(paths.count) }));
            """)
        return r
    }

    /// 点击（ref 或 selector；仅用于非发布类控件，发布类动作被 App 层禁止）
    public func click(target: String, label: String) async throws -> String {
        let r = try await run(
            """
            await click(\(jsStr(target)), { label: \(jsStr(label)) });
            cliLog(JSON.stringify({ ok: true }));
            """)
        return r
    }

    /// 页面上下文只读求值（回读状态、校验）
    public func evaluate(js source: String) async throws -> String {
        let r = try await run(
            """
            const v = await js(String.raw`\(source)`);
            cliLog(JSON.stringify({ ok: true, value: v }));
            """)
        return r
    }

    /// 结束标记（供 AgentLoop 判定任务完成）
    public struct Finish: Codable {
        public var status: String   // draftReady | needLogin | failed
        public var message: String
        public var draftURL: String?
        public init(status: String, message: String, draftURL: String? = nil) {
            self.status = status; self.message = message; self.draftURL = draftURL
        }
    }

    // MARK: - 执行内核

    /// 把一段官方 helper 调用包进"Space 恢复 + 单脚本执行 + 结果提取"
    func run(_ body: String) async throws -> String {
        let script = """
        const task = await useOrCreateTaskSpace(\(jsStr(spaceName)));
        try {
          \(body)
        } catch (e) {
          cliLog(JSON.stringify({ ok: false, error: String(e && e.message || e) }));
        }
        """
        let result = try await engine.runRaw(script: script, timeout: 120)
        // EgoLiteEngine 已提取最后一行 JSON；此处还原为字符串供上层（LLM）阅读
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
