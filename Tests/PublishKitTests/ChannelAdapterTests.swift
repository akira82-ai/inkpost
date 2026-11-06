import Foundation
import AppKit
import Testing
@testable import PublishKit

@MainActor
struct ChannelAdapterTests {
    private let config = LLMConfig(baseURL: "https://unused.invalid", apiKey: "test", model: "test")
    private func bridge() throws -> EgoBridge { try EgoBridge(spaceName: "fake", engine: EgoLiteEngine(binaryPath: "/usr/bin/false")) }

    @Test func structuredRequestAndLoginResumeReusePage() async throws {
        let adapter = RecordingAdapter()
        var pages = 0
        let service = AgentDispatchService(registryFactory: { .init([adapter]) }, bridgeFactory: { _ in pages += 1; return try bridge() })
        let task = UUID()
        try await service.beginTask(id: task)
        let request = ChannelRequest(title: "Title", body: "Complete\nbody", html: "<p>Complete</p>", tags: ["swift"], assets: ["image"])
        let first = try await service.execute(request: request, execution: .init(taskID: task, platform: .weibo), command: .prepare, config: config, onEvent: { _ in })
        #expect(first.failure?.code == .loginRequired)
        let invalid = try await service.execute(request: .init(title: "", body: "changed"), execution: .init(taskID: task, platform: .weibo), command: .resumeAfterUser, config: config, onEvent: { _ in })
        #expect(invalid.failure?.code == .invalidCommand)
        let second = try await service.execute(request: request, execution: .init(taskID: task, platform: .weibo), command: .resumeAfterUser, config: config, onEvent: { _ in })
        #expect(second == .readyForReview(message: "verified"))
        #expect(adapter.requests == [request, request])
        #expect(adapter.commands == [.prepare, .resumeAfterUser])
        #expect(pages == 1)
        let duplicate = try await service.execute(request: request, execution: .init(taskID: task, platform: .weibo), command: .prepare, config: config, onEvent: { _ in })
        #expect(duplicate.failure?.code == .invalidCommand)
    }

    @Test func failureIsolationAndValidationBeforeBrowser() async throws {
        let adapter = RecordingAdapter(fail: true)
        let other = RecordingAdapter(platform: .jike)
        var pages = 0
        let service = AgentDispatchService(registryFactory: { .init([adapter, other]) }, bridgeFactory: { _ in pages += 1; return try bridge() })
        let task = UUID(); try await service.beginTask(id: task)
        let request = ChannelRequest(title: "", body: "Body")
        for platform in [PlatformID.x, .weibo, .jike] {
            let outcome = try await service.execute(request: request, execution: .init(taskID: task, platform: platform), command: .prepare, config: config, onEvent: { _ in })
            if platform == .x { #expect(outcome.failure?.recovery == .notRecoverable) }
            if platform == .weibo { #expect(outcome.failure?.code == .operationResultUnknown); #expect(outcome.failure?.recovery == .inspectionRequired) }
        }
        #expect(other.requests.count == 1)
        #expect(pages == 2)
        let invalid = try await service.execute(request: .init(title: "", body: ""), execution: .init(taskID: task, platform: .weibo), command: .resumeAfterUser, config: config, onEvent: { _ in })
        #expect(invalid.failure?.code == .invalidCommand)
        try await service.beginTask(id: task)
        let tooMany = try await service.execute(request: .init(title: "", body: "Body", assets: ["a", "b"]), execution: .init(taskID: task, platform: .weibo), command: .prepare, config: config, onEvent: { _ in })
        #expect(tooMany.failure?.code == .contentUnsupported)
        #expect(pages == 2)
    }

    @Test func newTaskCreatesFreshAdapterSession() async throws {
        var created: [RecordingAdapter] = []
        let service = AgentDispatchService(registryFactory: { let adapter = RecordingAdapter(); created.append(adapter); return .init([adapter]) }, bridgeFactory: { _ in try bridge() })
        for _ in 0..<2 {
            let task = UUID(); try await service.beginTask(id: task)
            let result = try await service.execute(request: .init(title: "", body: "Body"), execution: .init(taskID: task, platform: .weibo), command: .prepare, config: config, onEvent: { _ in })
            #expect(result.failure?.code == .loginRequired)
        }
        #expect(created.count == 3)
        #expect(created[1].requests.count == 1 && created[2].requests.count == 1)
    }

    @Test func finishedContextRejectsLateEventsAndCancellationPropagates() async throws {
        var events: [ChannelEvent] = []
        let context = ChannelExecutionContext(execution: .init(taskID: UUID(), platform: .x), command: .prepare, bridge: try bridge(), config: config, onEvent: { events.append($0) })
        try context.advance(.fillingContent); context.finish()
        try context.advance(.verifyingContent); context.diagnostic("late")
        #expect(events.count == 1)
        let adapter = RecordingAdapter(cancel: true)
        let service = AgentDispatchService(registryFactory: { .init([adapter]) }, bridgeFactory: { _ in try bridge() })
        let taskID = UUID(); try await service.beginTask(id: taskID)
        do {
            _ = try await service.execute(request: .init(title: "", body: "Body"), execution: .init(taskID: taskID, platform: .weibo), command: .prepare, config: config, onEvent: { _ in })
            Issue.record("Cancellation swallowed")
        } catch { #expect(error is CancellationError) }
    }
    @Test func engineCancellationStopsWaitingForBrowserProcess() async throws {
        let executable = FileManager.default.temporaryDirectory.appendingPathComponent("ego-wait-\(UUID().uuidString)")
        try "#!/bin/sh\nexec /bin/sleep 30\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let engine = try EgoLiteEngine(binaryPath: executable.path)
        let operation = Task { try await engine.runRaw(script: "test") }
        try await Task.sleep(for: .milliseconds(100))
        let started = Date(); operation.cancel()
        do { _ = try await operation.value; Issue.record("Cancellation swallowed") }
        catch { #expect(error is CancellationError) }
        #expect(Date().timeIntervalSince(started) < 2)
    }

    @Test func agentWriteFailureStopsSubsequentTools() async throws {
        let executable = FileManager.default.temporaryDirectory.appendingPathComponent("ego-error-\(UUID().uuidString)")
        try "#!/bin/sh\n/bin/cat >/dev/null\necho '{\"ok\":false,\"error\":\"paste result unknown\"}'\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let bridge = try EgoBridge(spaceName: "fake", engine: EgoLiteEngine(binaryPath: executable.path))
        let calls = [ToolCall(id: "write", function: .init(name: "fill", arguments: "{\"target\":\"#body\",\"text\":\"Body\"}")),
                     ToolCall(id: "finish", function: .init(name: "finish", arguments: "{\"status\":\"draftReady\",\"message\":\"incorrect success\"}"))]
        do {
            _ = try await AgentExecutor.run(llm: ScriptedLLM([.toolCalls(calls)]), bridge: bridge, goal: "test", onEvent: { _ in })
            Issue.record("Unknown write result allowed finish")
        } catch {
            #expect((error as? ChannelFailure)?.code == .operationResultUnknown)
            #expect((error as? ChannelFailure)?.recovery == .inspectionRequired)
        }
    }

    /// Exercise the real fixture adapter, AgentLoop and verifier with a controlled DOM transport.
    @Test(arguments: ["valid", "body", "title", "tags", "images"])
    func realAdapterRejectsIncompleteContent(_ defect: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("ego-stub")
        let values: [String: [String: Any]] = [
            "#editor": ["text": defect == "body" ? "Body truncated" : "Body", "files": 0, "images": 0],
            "#title": ["text": defect == "title" ? "wrong" : "Title"],
            "#tags": ["text": defect == "tags" ? "" : "#swift"],
            "#files": ["files": defect == "images" ? 0 : 1, "images": 0]
        ]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: values), as: UTF8.self)
        let source = """
        #!/usr/bin/python3
        import sys,json
        script=sys.stdin.read()
        values=json.loads(\(String(reflecting: json)))
        target=next((key for key in values if key in script), None)
        print(json.dumps({"ok":True,"value":values.get(target,{})}))
        """
        try source.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let finish = ToolCall(id: "finish", function: .init(name: "finish", arguments: "{\"status\":\"draftReady\",\"message\":\"done\",\"body_target\":\"#editor\",\"title_target\":\"#title\",\"image_target\":\"#files\"}"))
        let adapter = FixtureChannelAdapter(makeLLM: { _ in ScriptedLLM([.toolCalls([finish])]) })
        let service = AgentDispatchService(registryFactory: { .init([adapter]) }, bridgeFactory: { _ in try EgoBridge(spaceName: "stub", engine: EgoLiteEngine(binaryPath: executable.path)) })
        let taskID = UUID(); try await service.beginTask(id: taskID)
        let result = try await service.execute(request: .init(title: "Title", body: "Body", tags: ["swift"], assets: ["image"]), execution: .init(taskID: taskID, platform: .simFixture), command: .prepare, config: config, onEvent: { _ in })
        if defect == "valid" { #expect(result == .readyForReview(message: "done")) }
        else { #expect(result.failure?.code == .verificationFailed); #expect(result.failure?.recovery == .inspectionRequired) }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["INKPOST_BROWSER_TESTS"] == "1"))
    func realFixtureAdapterBrowserSmoke() async throws {
        let url = try Resources.url("fixture-page", ext: "html", sub: "Fixtures")
        func call(_ name: String, _ args: [String: Any]) throws -> AssistantTurn {
            .toolCalls([.init(id: UUID().uuidString, function: .init(name: name, arguments: String(decoding: try JSONSerialization.data(withJSONObject: args), as: UTF8.self)))])
        }
        let image = FileManager.default.temporaryDirectory.appendingPathComponent("contract-smoke-\(UUID().uuidString).png")
        try Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!.write(to: image)
        let turns = try [
            call("navigate", ["url": url.absoluteString]),
            call("snapshot", [:]),
            call("fill", ["target": "#title", "text": "Contract smoke"]),
            call("paste_html", ["target": "#editor", "html": "<p>Complete body</p>"]),
            call("fill", ["target": "#tags", "text": "#swift #test"]),
            call("upload", ["target": "#files", "paths": [image.path]]),
            call("finish", ["status": "draftReady", "message": "verified", "title_target": "#title", "body_target": "#editor", "image_target": "#files"])
        ]
        let adapter = FixtureChannelAdapter(makeLLM: { _ in ScriptedLLM(turns) })
        let service = AgentDispatchService(registryFactory: { .init([adapter]) })
        let taskID = UUID(); try await service.beginTask(id: taskID)
        let result = try await service.execute(request: .init(title: "Contract smoke", body: "Complete body", html: "<p>Complete body</p>", tags: ["swift", "test"], assets: [image.path]), execution: .init(taskID: taskID, platform: .simFixture), command: .prepare, config: config, onEvent: { _ in })
        #expect(result == .readyForReview(message: "verified"))
        let id = try #require(service.workspaceID)
        let check = try await EgoLiteEngine().runRaw(script: "const task = await taskSpace(\(id)); const page = task.page('p1'); cliLog(JSON.stringify({unpublished: await page.evaluate(() => !document.querySelector('#receipt').dataset.url)}));")
        #expect(check.bool("unpublished") == true)
        if result.failure == nil {
            _ = try await EgoLiteEngine().runRaw(script: "const task = await taskSpace(\(id)); await task.finish({keep:[]}); cliLog(JSON.stringify({ok:true}));")
        }
    }

}

private final class RecordingAdapter: ChannelAdapter {
    let platform: PlatformID
    let capabilities = ChannelCapabilities(usesTitle: false, requiresLLM: false, maximumImages: 1)
    var requests: [ChannelRequest] = []
    var commands: [ChannelCommand] = []
    let fail: Bool
    let cancel: Bool
    init(platform: PlatformID = .weibo, fail: Bool = false, cancel: Bool = false) { self.platform = platform; self.fail = fail; self.cancel = cancel }
    @MainActor func execute(request: ChannelRequest, context: ChannelExecutionContext) async throws -> ChannelOutcome {
        requests.append(request); commands.append(context.command)
        try context.advance(.fillingContent)
        if cancel { throw CancellationError() }
        if fail { throw EgoBridge.BridgeError.toolFailed("adapter failure") }
        return requests.count == 1 ? .waitingForUser(.init(code: .loginRequired, stage: .checkingLogin, detail: "login", recovery: .loginRequired)) : .readyForReview(message: "verified")
    }
}

@Suite(.serialized)
@MainActor
struct ClipboardContractTests {
    @Test func leasesExcludeEachOtherAndRestoreOwnedCopies() throws {
        let board = NSPasteboard(name: .init("inkpost-test-\(UUID().uuidString)"))
        board.clearContents(); board.setString("original", forType: .string)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("clipboard-\(UUID().uuidString).png")
        try Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!.write(to: file)
        let lease = try ImageClipboardSession.acquire(clipboard: board)
        defer { lease.restore() }
        do { _ = try ImageClipboardSession.acquire(clipboard: board); Issue.record("Overlapping lease accepted") }
        catch { #expect((error as? ChannelFailure)?.recovery == .retryAllowed) }
        try lease.writePNG(path: file.path)
        #expect(board.data(forType: .png) != nil)
        lease.restore(); lease.restore()
        #expect(board.string(forType: .string) == "original")
        let next = try ImageClipboardSession.acquire(clipboard: board)
        defer { next.restore() }
        try next.writePNG(path: file.path)
        board.clearContents(); board.setString("new user copy", forType: .string)
        next.restore()
        #expect(board.string(forType: .string) == "new user copy")
    }

    @Test func nativePasteLeaseReleasesAfterFailure() async throws {
        do {
            let _: Void = try await ClipboardPasteService.withTextPaste { throw CancellationError() }
            Issue.record("Cancellation swallowed")
        } catch { #expect(error is CancellationError) }
        let board = NSPasteboard(name: .init("inkpost-test-\(UUID().uuidString)"))
        let lease = try ImageClipboardSession.acquire(clipboard: board)
        lease.restore()
    }
}

@MainActor
struct ZhihuAdapterTests {
    private let config = LLMConfig(baseURL: "https://unused.invalid", apiKey: "", model: "unused")
    private let request = ChannelRequest(title: "知乎「标题」& 🖋️", body: "第一段  空格\n\n第二段", tags: ["测试"])

    @Test func missingTitleIsRejectedBeforeAllocatingPage() async throws {
        var pages = 0
        let service = AgentDispatchService(registryFactory: { .init([ZhihuChannelAdapter()]) }, bridgeFactory: { _ in
            pages += 1
            return try EgoBridge(spaceName: "unused", engine: EgoLiteEngine(binaryPath: "/usr/bin/false"))
        })
        let task = UUID(); try await service.beginTask(id: task)
        let result = try await service.execute(request: .init(title: " \n", body: "正文"), execution: .init(taskID: task, platform: .zhihu), command: .prepare, config: config, onEvent: { _ in })
        #expect(result.failure?.code == .contentUnsupported)
        #expect(result.failure?.recovery == .contentChangeRequired)
        #expect(pages == 0)
    }

    @Test(arguments: ["valid", "titleRejected", "bodyConflict", "login"])
    func realZhihuAdapterFillsAndVerifiesTitle(_ mode: String) async throws {
        let (bridge, log) = try transport(mode: mode)
        let service = AgentDispatchService(registryFactory: { .init([ZhihuChannelAdapter()]) }, bridgeFactory: { _ in bridge })
        let task = UUID(); try await service.beginTask(id: task)
        var result = try await service.execute(request: request, execution: .init(taskID: task, platform: .zhihu), command: .prepare, config: config, onEvent: { _ in })
        if mode == "login" {
            #expect(result.failure?.code == .loginRequired)
            result = try await service.execute(request: request, execution: .init(taskID: task, platform: .zhihu), command: .resumeAfterUser, config: config, onEvent: { _ in })
        }
        let scriptLog = try String(contentsOf: log, encoding: .utf8)
        if ["valid", "login"].contains(mode) {
            #expect(result.failure == nil)
            #expect(scriptLog.contains("await page.fill"))
            #expect(scriptLog.contains(bridge.jsStr(request.title)))
        } else {
            #expect(result.failure?.code == .verificationFailed)
            #expect(result.failure?.recovery == .inspectionRequired)
        }
        if mode == "bodyConflict" { #expect(!scriptLog.contains("await page.fill")) }
        #expect(!scriptLog.contains("Escape"))
        #expect(!scriptLog.contains("Meta+V")) // zero-image flow
    }

    @Test func logicalParagraphVerificationPreservesWhitespaceAndLimits() throws {
        let valid = ZhihuChannelAdapter.PageState(title: request.title, body: request.taggedBody.replacingOccurrences(of: "\n", with: "\r\n"), titleLimit: nil, titleValid: true, images: [])
        try valid.checkContent(request, allowEmpty: false)
        let empty = ZhihuChannelAdapter.PageState(title: "", body: "", titleLimit: nil, titleValid: true, images: [])
        try empty.checkContent(request, allowEmpty: true)
        #expect(throws: ChannelFailure.self) { try empty.checkContent(request, allowEmpty: false) }
        for body in [request.taggedBody.replacingOccurrences(of: "\n\n", with: "\n"), request.taggedBody.replacingOccurrences(of: "  ", with: " "), "正文截断"] {
            let page = ZhihuChannelAdapter.PageState(title: request.title, body: body, titleLimit: nil, titleValid: true, images: [])
            #expect(throws: ChannelFailure.self) { try page.checkContent(request, allowEmpty: false) }
        }
        let limited = ZhihuChannelAdapter.PageState(title: "", body: "", titleLimit: 3, titleValid: true, images: [])
        do { try limited.checkContent(request, allowEmpty: true); Issue.record("Title limit ignored") }
        catch { #expect((error as? ChannelFailure)?.recovery == .contentChangeRequired) }
    }

    @Test func imageRecoveryRejectsReplacementReorderingAndUnknownPaste() throws {
        typealias Image = ZhihuChannelAdapter.ImageState
        let a = Image(identity: "https://pic.zhihu.com/a", ready: true)
        let b = Image(identity: "https://pic.zhihu.com/b", ready: true)
        let checkpoint = ZhihuChannelAdapter.ImageProgress(confirmed: [a.identity, b.identity])
        try checkpoint.validate([a, b])
        for images in [[b, a], [a], [a, a], [a, Image(identity: b.identity, ready: false)]] {
            #expect(throws: ChannelFailure.self) { try checkpoint.validate(images) }
        }
        let pending = ZhihuChannelAdapter.ImageProgress(confirmed: [a.identity], pending: 1)
        try pending.validate([a, Image(identity: "blob:pending", ready: false)])
        do { try pending.validate([a]); Issue.record("Unknown paste accepted for repetition") }
        catch { #expect((error as? ChannelFailure)?.code == .operationResultUnknown) }
        #expect(throws: ChannelFailure.self) { try ZhihuChannelAdapter.ImageProgress().validate([a]) }
    }

    private func transport(mode: String) throws -> (EgoBridge, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("ego-zhihu-stub")
        let log = directory.appendingPathComponent("scripts.log")
        let values: [String: Any] = ["title": request.title, "body": request.taggedBody]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: values), as: UTF8.self)
        let source = """
        #!/usr/bin/python3
        import sys,json,pathlib
        root=pathlib.Path(__file__).parent
        script=sys.stdin.read()
        with (root/'scripts.log').open('a') as log: log.write(script+'\\n')
        statefile=root/'state.json'
        state=json.loads(statefile.read_text()) if statefile.exists() else {'title':'','opens':0}
        expected=json.loads(\(String(reflecting: json)))
        mode=\(String(reflecting: mode))
        result={'ok':True}
        if 'zhihu:open-editor' in script:
            state['opens']+=1
            result.update({'loginRequired':True} if mode=='login' and state['opens']==1 else {'composerReady':True})
        elif 'await page.fill' in script:
            state['title']=expected['title'] if mode!='titleRejected' else 'truncated'
        elif 'zhihu:read-page' in script:
            result['value']={'title':state['title'],'body':expected['body'] if mode!='bodyConflict' else 'other content',
                'titleLimit':None,'titleValid':True,'images':[]}
        statefile.write_text(json.dumps(state))
        print(json.dumps(result))
        """
        try source.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        return (try EgoBridge(spaceName: "zhihu-stub", engine: EgoLiteEngine(binaryPath: executable.path)), log)
    }
}
