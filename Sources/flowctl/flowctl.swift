import Foundation
import PublishKit

/// flowctl —— 引擎冒烟/演示工具（无 UI）。
///
///   flowctl demo    全链路：prepare → (模拟人工) → finalize
///   flowctl prepare 仅跑填充
///   flowctl finalize 仅回读（需先在 ego 浏览器点「确认发布」）
///
/// 演示全流程会用到的资源（适配器、fixture 页）随包内置于 Bundle。

@main
struct FlowCTL {
    static func main() async {
        let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "demo"

        do {
            let engine = try EgoLiteEngine()
            let adapterPath = try Resources.path("sim", ext: "mjs", sub: "Adapters")
            let fixtureURL = try Resources.url("fixture-page", ext: "html", sub: "Fixtures")

            let task = try makeSmokeTask(fixtureURL: fixtureURL)
            print("▸ 任务: \(task.postId)  space=\(task.spaceName)")
            print("▸ ego-browser: \(engine.binaryPath)")

            switch mode {
            case "demo":
                try await runDemo(engine: engine, adapterPath: adapterPath, task: task)
            case "prepare":
                try await runPrepare(engine: engine, adapterPath: adapterPath, task: task)
            case "finalize":
                try await runFinalize(engine: engine, adapterPath: adapterPath, task: task)
            case "cleanup":
                await cleanupSmokeSpaces(engine: engine)
            case "dumpscript":
                let script = EgoLiteEngine.taskScript(adapterPath: adapterPath, task: task, step: "prepare")
                print(script)
            case "compact-smoke":
                try await runCompactSmoke(engine: engine, fixtureURL: fixtureURL, task: task)
            case "agent-demo":
                try await runAgentDemo(engine: engine, fixtureURL: fixtureURL, task: task)
            default:
                print("未知模式 \(mode)，可用: demo / prepare / finalize / cleanup")
                exit(2)
            }
            exit(0)
        } catch {
            fputs("✗ \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    // MARK: - 流程

    static func runDemo(engine: EgoLiteEngine, adapterPath: String, task: PublishTask) async throws {
        print("\n== 第 1 步：prepare（填充草稿）==")
        let r1 = try await engine.prepare(adapterPath: adapterPath, task: task)
        guard let phase = r1.string("phase") else {
            throw DemoError("prepare 未返回 phase。输出：\n\(r1.rawOutput)")
        }
        print("  phase=\(phase)  message=\(r1.string("message") ?? "-")")
        guard phase == "awaitingConfirm" else { throw DemoError("prepare 失败：\(r1.string("message") ?? "?")") }

        print("\n== 第 2 步：模拟人工确认（真实产品中由用户在 ego 浏览器点击）==")
        let humanAdapter = try Resources.path("simulate-human", ext: "mjs", sub: "Adapters")
        _ = try await engine.run(adapter: humanAdapter, task: task, step: "click", timeout: 60)
        print("  已点击「确认发布」")

        print("\n== 第 3 步：finalize（回读发布结果）==")
        let r3 = try await engine.finalize(adapterPath: adapterPath, task: task)
        guard r3.string("phase") == "published", let url = r3.string("url") else {
            throw DemoError("finalize 未获得发布回执：\(r3.string("message") ?? "?")")
        }
        print("  ✅ 发布成功，回执链接：\(url)")
    }

    static func runPrepare(engine: EgoLiteEngine, adapterPath: String, task: PublishTask) async throws {
        let r = try await engine.prepare(adapterPath: adapterPath, task: task)
        print("phase=\(r.string("phase") ?? "?")  message=\(r.string("message") ?? "-")")
        if r.string("phase") != "awaitingConfirm" { throw DemoError("prepare 失败") }
        print("\n请在 ego 浏览器检查草稿；完成后运行: flowctl finalize")
    }

    static func runFinalize(engine: EgoLiteEngine, adapterPath: String, task: PublishTask) async throws {
        let r = try await engine.finalize(adapterPath: adapterPath, task: task)
        print("phase=\(r.string("phase") ?? "?")  url=\(r.string("url") ?? "-")  message=\(r.string("message") ?? "-")")
        guard r.string("phase") == "published" else { throw DemoError("尚未完成发布") }
        print("✅ 回执：\(r.string("url") ?? "")")
    }

    // MARK: - 极简 agent 管道验证（假模型，不打真实 LLM API）

    static func runAgentDemo(engine: EgoLiteEngine, fixtureURL: URL, task: PublishTask) async throws {
        let bridge = try EgoBridge(spaceName: task.spaceName, engine: engine)
        let url = fixtureURL.absoluteString

        func argsJSON(_ dict: [String: Any]) -> String {
            let d = try! JSONSerialization.data(withJSONObject: dict)
            return String(data: d, encoding: .utf8) ?? "{}"
        }
        func call(_ id: String, _ name: String, _ args: [String: Any]) -> AssistantTurn {
            .toolCalls([ToolCall(id: id, function: .init(name: name, arguments: argsJSON(args)))])
        }

        // 假模型脚本：真实产品里这里是 GLM 等兼容模型；本演示用于验证循环与工具层管道
        let scripted = ScriptedLLM([
            call("t1", "navigate", ["url": url]),
            call("t2", "fill", ["target": "input#title", "text": "agent 引擎冒烟"]),
            call("t3", "paste_html", ["target": "#editor", "html": "<p>第一段：<b>加粗</b>验证。</p><p>第二段：agent 路线。</p>"]),
            call("t4", "upload", ["target": "input#files", "paths": [task.assets.first?.path ?? ""]]),
            call("t5", "inspect", ["target": "input#title"]),
            call("t6", "finish", ["status": "draftReady", "message": "模拟平台草稿就绪", "draft_url": url]),
        ])

        print("\n== agent 填充（假模型驱动真实工具层）==")
        let result = try await AgentExecutor.run(llm: scripted, bridge: bridge,
            goal: "把测试内容填入模拟平台页面，停在草稿。",
            onEvent: { print("  [agent] \($0)") })
        guard result.status == "draftReady" else {
            throw DemoError("agent 未能就绪：\(result.message)")
        }

        print("\n== 模拟人工确认（产品中由用户在 ego 浏览器点击）==")
        _ = try await bridge.click(target: "#publish-btn", label: "模拟人工点击确认发布")
        _ = try await bridge.evaluate(js: "0")

        print("\n== 回读回执 ==")
        let receipt = try await bridge.evaluate(js: "document.querySelector('#receipt') && document.querySelector('#receipt').dataset.url || ''")
        print("  回执原始输出：\(receipt.prefix(200))")
        print("\n✅ 极简 agent 管道端到端通过（LLM 就绪后把 ScriptedLLM 换成 OpenAICompatClient 即为真实产品）")
    }

    /// Verify explicit page isolation without publishing even to the fixture.
    static func runCompactSmoke(engine: EgoLiteEngine, fixtureURL: URL, task: PublishTask) async throws {
        let first = try EgoBridge(spaceName: task.spaceName, engine: engine)
        _ = try await first.navigate(url: fixtureURL.absoluteString)
        _ = try await first.fill(target: "#title", text: "First channel")
        let nameData = try JSONSerialization.data(withJSONObject: [task.spaceName])
        let name = String(decoding: nameData, as: UTF8.self)
        let secondPage = try await engine.runRaw(script: "const task = await taskSpace(\(name)[0]); const page = await task.newPage(); cliLog(JSON.stringify({label: page.label}));")
        guard let label = secondPage.string("label"), label != "p1" else { throw DemoError("Second page not created") }
        let second = try EgoBridge(spaceName: task.spaceName, engine: engine, pageLabel: label)
        _ = try await second.navigate(url: fixtureURL.absoluteString)
        _ = try await second.fill(target: "#title", text: "Second channel")
        _ = try await first.pasteHTML(target: "#editor", html: "<p>Independent content</p>", plainFallback: "Independent content")
        _ = try await first.upload(target: "#files", paths: task.assets.map(\.path))
        func value(_ output: String) throws -> [String: Any] {
            let object = try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any]
            guard let value = object?["value"] as? [String: Any] else { throw DemoError("Invalid inspection result") }
            return value
        }
        let firstTitle = try value(await first.inspect(target: "#title"))
        let secondTitle = try value(await second.inspect(target: "#title"))
        let body = try value(await first.inspect(target: "#editor"))
        let files = try value(await first.inspect(target: "#files"))
        guard firstTitle["text"] as? String == "First channel", secondTitle["text"] as? String == "Second channel",
              body["text"] as? String == "Independent content", files["files"] as? Int == 1 else { throw DemoError("Page isolation or content verification failed") }
        _ = try await engine.runRaw(script: "const task = await taskSpace(\(name)[0]); await task.finish({keep: []}); cliLog(JSON.stringify({ok:true}));")
        print("✅ One Space / two Pages: isolated titles, rich text and upload verified; no publish action.")
    }

    // MARK: - Space 清理

    /// 关闭所有冒烟测试遗留的 Space（名字以 "publish post " 开头）
    static func cleanupSmokeSpaces(engine: EgoLiteEngine) async {
        let script = """
        const spaces = await listTaskSpaces();
        const targets = spaces.filter(s => (s.name || "").startsWith("publish post "));
        let closed = 0, skipped = 0;
        for (const s of targets) {
          try {
            const t = await taskSpace(s.name);
            await t.finish({ keep: [] });
            closed++;
          } catch (e) {
            skipped++;
          }
        }
        cliLog(JSON.stringify({ total: spaces.length, targets: targets.length, closed, skipped }));
        """
        do {
            let r = try await engine.runRaw(script: script, timeout: 120)
            print("清理完成：\(r.string("closed") ?? "?") 个 Space（共 \(r.string("targets") ?? "?") 个目标，\(r.string("skipped") ?? "0") 个跳过）")
        } catch {
            fputs("✗ 清理失败：\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    // MARK: - 数据

    static func makeSmokeTask(fixtureURL: URL) throws -> PublishTask {
        // 生成一张 1x1 PNG 作为测试素材
        let pngB64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("publishflow-smoke-\(UUID().uuidString.prefix(6)).png")
        try Data(base64Encoded: pngB64)?.write(to: tmp)

        let postID = "smoke-" + UUID().uuidString.prefix(8)
        return PublishTask(
            postId: String(postID),
            spaceName: "publish post \(postID)",
            article: Article(
                title: "引擎冒烟测试",
                markdown: "第一段：**加粗**验证。\n\n第二段：[链接](https://example.com)验证。",
                html: "<p>第一段：<b>加粗</b>验证。</p><p>第二段：<a href=\"https://example.com\">链接</a>验证。</p>",
                tags: ["测试"]
            ),
            assets: [TaskAsset(id: "a1", fileName: tmp.lastPathComponent, mimeType: "image/png", path: tmp.path)],
            target: TaskTarget(platform: .simFixture, editorURL: fixtureURL.absoluteString)
        )
    }

    static func requireResource(_ name: String, ext: String, sub: String) throws -> String {
        try Resources.path(name, ext: ext, sub: sub)
    }

    static func requireResourceURL(_ name: String, ext: String, sub: String) throws -> URL {
        try Resources.url(name, ext: ext, sub: sub)
    }
}

struct DemoError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}
