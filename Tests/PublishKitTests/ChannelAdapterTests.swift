import Foundation
import AppKit
import UniformTypeIdentifiers
import Testing
@testable import PublishKit

@MainActor
struct ChannelAdapterTests {

    private func bridge() throws -> EgoBridge { try EgoBridge(spaceName: "fake", engine: EgoLiteEngine(binaryPath: "/usr/bin/false")) }

    @Test func structuredRequestAndLoginResumeReusePage() async throws {
        let adapter = RecordingAdapter()
        var pages = 0
        let service = DispatchService(registryFactory: { .init([adapter]) }, bridgeFactory: { _ in pages += 1; return try bridge() })
        let task = UUID()
        try await service.beginTask(id: task)
        let request = ChannelRequest(title: "Title", body: "Complete\nbody", html: "<p>Complete</p>", tags: ["swift"], assets: [try testAssetFile(type: .tiff).path])
        let first = try await service.execute(request: request, execution: .init(taskID: task, platform: .weibo), command: .prepare, onEvent: { _ in })
        #expect(first.failure?.code == .loginRequired)
        let invalid = try await service.execute(request: .init(title: "", body: "changed"), execution: .init(taskID: task, platform: .weibo), command: .resumeAfterUser, onEvent: { _ in })
        #expect(invalid.failure?.code == .invalidCommand)
        let second = try await service.execute(request: request, execution: .init(taskID: task, platform: .weibo), command: .resumeAfterUser, onEvent: { _ in })
        #expect(second == .readyForReview(message: "verified"))
        #expect(adapter.requests == [request, request])
        #expect(adapter.commands == [.prepare, .resumeAfterUser])
        #expect(adapter.uploads.count == 2 && adapter.uploads[0] == adapter.uploads[1])
        #expect(pages == 1)
        let duplicate = try await service.execute(request: request, execution: .init(taskID: task, platform: .weibo), command: .prepare, onEvent: { _ in })
        #expect(duplicate.failure?.code == .invalidCommand)
    }

    @Test func failureIsolationAndValidationBeforeBrowser() async throws {
        let adapter = RecordingAdapter(fail: true)
        let other = RecordingAdapter(platform: .jike)
        var pages = 0
        let service = DispatchService(registryFactory: { .init([adapter, other]) }, bridgeFactory: { _ in pages += 1; return try bridge() })
        let task = UUID(); try await service.beginTask(id: task)
        let request = ChannelRequest(title: "", body: "Body")
        for platform in [PlatformID.x, .weibo, .jike] {
            let outcome = try await service.execute(request: request, execution: .init(taskID: task, platform: platform), command: .prepare, onEvent: { _ in })
            if platform == .x { #expect(outcome.failure?.recovery == .notRecoverable) }
            if platform == .weibo { #expect(outcome.failure?.code == .operationResultUnknown); #expect(outcome.failure?.recovery == .inspectionRequired) }
        }
        #expect(other.requests.count == 1)
        #expect(pages == 2)
        let invalid = try await service.execute(request: .init(title: "", body: ""), execution: .init(taskID: task, platform: .weibo), command: .resumeAfterUser, onEvent: { _ in })
        #expect(invalid.failure?.code == .invalidCommand)
        try await service.beginTask(id: task)
        let tooMany = try await service.execute(request: .init(title: "", body: "Body", assets: ["a", "b"]), execution: .init(taskID: task, platform: .weibo), command: .prepare, onEvent: { _ in })
        #expect(tooMany.failure?.code == .contentUnsupported)
        #expect(pages == 2)
    }

    @Test func newTaskCreatesFreshAdapterSession() async throws {
        var created: [RecordingAdapter] = []
        let service = DispatchService(registryFactory: { let adapter = RecordingAdapter(); created.append(adapter); return .init([adapter]) }, bridgeFactory: { _ in try bridge() })
        for _ in 0..<2 {
            let task = UUID(); try await service.beginTask(id: task)
            let result = try await service.execute(request: .init(title: "", body: "Body"), execution: .init(taskID: task, platform: .weibo), command: .prepare, onEvent: { _ in })
            #expect(result.failure?.code == .loginRequired)
        }
        #expect(created.count == 3)
        #expect(created[1].requests.count == 1 && created[2].requests.count == 1)
    }

    @Test func channelsSharePreparedAssetsAndNewTasksUseFreshFiles() async throws {
        let first = RecordingAdapter(maximumImages: 2)
        let second = RecordingAdapter(platform: .jike, maximumImages: 2)
        let service = DispatchService(registryFactory: { .init([first, second]) }, bridgeFactory: { _ in try bridge() })
        let source = try testAssetFile(type: .tiff)
        let original = try Data(contentsOf: source)
        let otherSource = try testAssetFile(type: .jpeg)
        let request = ChannelRequest(title: " title ", body: " body\n\n ", html: "<p>unused</p>", tags: ["tag"], assets: [source.path, otherSource.path])
        let task = UUID(); try await service.beginTask(id: task)
        _ = try await service.execute(request: request, execution: .init(taskID: task, platform: .weibo), command: .prepare, onEvent: { _ in })
        let paths = try #require(first.uploads.first)
        // Prepared bytes are stable even if the original file changes after preparation.
        try Data("changed original".utf8).write(to: source)
        _ = try await service.execute(request: request, execution: .init(taskID: task, platform: .jike), command: .prepare, onEvent: { _ in })
        #expect(first.requests == [request] && second.requests == [request])
        #expect(second.uploads == [paths])
        #expect(paths.count == 2 && paths[0] != paths[1])
        _ = try AssetService.validatedPNG(Data(contentsOf: URL(fileURLWithPath: paths[0])))
        let nextTask = UUID()
        try await service.beginTask(id: nextTask)
        #expect(!FileManager.default.fileExists(atPath: paths[0]))
        #expect(FileManager.default.fileExists(atPath: source.path))
        try original.write(to: source)
        _ = try await service.execute(request: request, execution: .init(taskID: nextTask, platform: .weibo), command: .prepare, onEvent: { _ in })
        #expect(first.uploads.last != paths)
    }

    @Test func preparationFailureBlocksEveryChannelBeforeBrowser() async throws {
        let first = RecordingAdapter()
        let second = RecordingAdapter(platform: .jike)
        var pages = 0
        let service = DispatchService(registryFactory: { .init([first, second]) }, bridgeFactory: { _ in pages += 1; return try bridge() })
        let task = UUID(); try await service.beginTask(id: task)
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tiff")
        let request = ChannelRequest(title: "", body: "Body", assets: [missing.path])
        let failure = try await service.execute(request: request, execution: .init(taskID: task, platform: .weibo), command: .prepare, onEvent: { _ in })
        #expect(failure.failure?.stage == .validatingRequest)
        // Fixing an external path must not silently alter the failed task's snapshot.
        try Data(contentsOf: testAssetFile()).write(to: missing)
        let other = try await service.execute(request: request, execution: .init(taskID: task, platform: .jike), command: .prepare, onEvent: { _ in })
        #expect(other == failure)
        #expect(pages == 0 && first.requests.isEmpty && second.requests.isEmpty)
    }

    @Test func adapterRejectsUnpreparedImagesBeforeBrowser() async throws {
        let request = ChannelRequest(title: "Title", body: "Body", assets: [try testAssetFile(type: .tiff).path])
        for adapter in [ZhihuChannelAdapter(), XChannelAdapter(), JikeChannelAdapter(), FixtureChannelAdapter()] as [any ChannelAdapter] {
            let context = ChannelExecutionContext(execution: .init(taskID: UUID(), platform: adapter.platform), command: .prepare, bridge: try bridge(), onEvent: { _ in })
            do { _ = try await adapter.execute(request: request, context: context); Issue.record("Missing PNG preparation accepted") }
            catch { #expect((error as? ChannelFailure)?.code == .invalidCommand) }
        }
    }

    @Test func finishedContextRejectsLateEventsAndCancellationPropagates() async throws {
        var events: [ChannelEvent] = []
        let context = ChannelExecutionContext(execution: .init(taskID: UUID(), platform: .x), command: .prepare, bridge: try bridge(), onEvent: { events.append($0) })
        try context.advance(.fillingContent); context.finish()
        try context.advance(.verifyingContent); context.diagnostic("late")
        #expect(events.count == 1)
        let adapter = RecordingAdapter(cancel: true)
        let service = DispatchService(registryFactory: { .init([adapter]) }, bridgeFactory: { _ in try bridge() })
        let taskID = UUID(); try await service.beginTask(id: taskID)
        do {
            _ = try await service.execute(request: .init(title: "", body: "Body"), execution: .init(taskID: taskID, platform: .weibo), command: .prepare, onEvent: { _ in })
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


}

private final class RecordingAdapter: ChannelAdapter {
    let platform: PlatformID
    let capabilities: ChannelCapabilities
    var requests: [ChannelRequest] = []
    var commands: [ChannelCommand] = []
    var uploads: [[String]] = []
    let fail: Bool
    let cancel: Bool
    init(platform: PlatformID = .weibo, fail: Bool = false, cancel: Bool = false, maximumImages: Int = 1) {
        self.platform = platform; self.fail = fail; self.cancel = cancel
        capabilities = ChannelCapabilities(usesTitle: false, maximumImages: maximumImages)
    }
    @MainActor func execute(request: ChannelRequest, context: ChannelExecutionContext) async throws -> ChannelOutcome {
        requests.append(request); commands.append(context.command)
        uploads.append(try context.uploadPaths(for: request))
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
        #expect(board.data(forType: .png) == (try Data(contentsOf: file)))
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

    @Test func clipboardRejectsNonPNGWithoutConvertingOrChangingClipboard() throws {
        let board = NSPasteboard(name: .init("inkpost-test-\(UUID().uuidString)"))
        board.clearContents(); board.setString("user copy", forType: .string)
        let lease = try ImageClipboardSession.acquire(clipboard: board)
        defer { lease.restore() }
        #expect(throws: (any Error).self) { try lease.writePNG(path: testAssetFile(type: .tiff).path) }
        #expect(board.string(forType: .string) == "user copy")
    }
}

@MainActor
struct ZhihuAdapterTests {

    private let request = ChannelRequest(title: "知乎「标题」& 🖋️", body: "第一段  空格\n\n第二段", tags: ["测试"])

    @Test func oversizedTitleIsRejectedBeforeAllocatingPage() async throws {
        var pages = 0
        let service = DispatchService(registryFactory: { .init([ZhihuChannelAdapter()]) }, bridgeFactory: { _ in
            pages += 1
            return try EgoBridge(spaceName: "unused", engine: EgoLiteEngine(binaryPath: "/usr/bin/false"))
        })
        let task = UUID(); try await service.beginTask(id: task)
        let result = try await service.execute(request: .init(title: String(repeating: "中", count: 45), body: "正文"), execution: .init(taskID: task, platform: .zhihu), command: .prepare, onEvent: { _ in })
        #expect(result.failure?.code == .contentUnsupported)
        #expect(result.failure?.recovery == .contentChangeRequired)
        #expect(pages == 0)
    }

    @Test(arguments: ["valid", "titleRejected", "bodyConflict", "login"])
    func realZhihuAdapterFillsAndVerifiesTitle(_ mode: String) async throws {
        let (bridge, log) = try transport(mode: mode)
        let service = DispatchService(registryFactory: { .init([ZhihuChannelAdapter()]) }, bridgeFactory: { _ in bridge })
        let task = UUID(); try await service.beginTask(id: task)
        var result = try await service.execute(request: request, execution: .init(taskID: task, platform: .zhihu), command: .prepare, onEvent: { _ in })
        if mode == "login" {
            #expect(result.failure?.code == .loginRequired)
            result = try await service.execute(request: request, execution: .init(taskID: task, platform: .zhihu), command: .resumeAfterUser, onEvent: { _ in })
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

    @Test func zhihuCharacterBoundariesAndOptionalFields() throws {
        let capabilities = ZhihuChannelAdapter().capabilities
        try PlatformRules.validate(.init(title: "", body: "正文"), capabilities: capabilities)
        try PlatformRules.validate(.init(title: String(repeating: "中", count: 44), body: String(repeating: "文", count: 1899)), capabilities: capabilities)
        try PlatformRules.validate(.init(title: String(repeating: "🖋️", count: 44), body: "正文"), capabilities: capabilities)
        for request in [ChannelRequest(title: String(repeating: "中", count: 45), body: "正文"),
                        .init(title: "", body: String(repeating: "文", count: 1900)),
                        .init(title: "", body: String(repeating: "文", count: 1898), tags: ["标签"]),
                        .init(title: "标题", body: " \n")] {
            #expect(throws: ChannelFailure.self) { try PlatformRules.validate(request, capabilities: capabilities) }
        }
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

@MainActor
struct DeterministicFixtureTests {
    @Test(arguments: ["valid", "body", "title", "tags", "images", "writeFailure"])
    func verifiesRealAdapterAndStopsUnknownWrites(_ defect: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let binary = directory.appendingPathComponent("fixture-stub")
        let source = #"""
        #!/usr/bin/python3
        import sys,json,pathlib,re
        root=pathlib.Path(__file__).parent
        script=sys.stdin.read()
        with (root/'log').open('a') as log: log.write(script+'\n')
        path=root/'state'
        state=json.loads(path.read_text()) if path.exists() else {'#title':'','#editor':'','#tags':'','#files':0}
        defect=DEFECT
        result={'ok':True}
        match=re.search(r'await page.fill\(("(?:\\.|[^"\\])*"), ("(?:\\.|[^"\\])*")\)',script)
        if match:
            key,value=map(json.loads,match.groups())
            if defect=='writeFailure': result={'ok':False,'error':'write result unknown'}
            else: state[key]=value
        if 'await page.setInputFiles' in script: state['#files']=0 if defect=='images' else 1
        if 'const el = document.querySelector' in script:
            key=next(k for k in state if k in script)
            value=state[key]
            if value and defect=={'#title':'title','#editor':'body','#tags':'tags'}.get(key):value='truncated'
            result['value']={'files':value} if key=='#files' else {'text':value}
        path.write_text(json.dumps(state))
        print(json.dumps(result))
        """#.replacingOccurrences(of: "DEFECT", with: String(reflecting: defect))
        try source.write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
        let service = DispatchService(registryFactory: { .init([FixtureChannelAdapter()]) }, bridgeFactory: { _ in
            try EgoBridge(spaceName: "fixture-stub", engine: EgoLiteEngine(binaryPath: binary.path))
        })
        let task = UUID(); try await service.beginTask(id: task)
        let result = try await service.execute(request: .init(title: "Title", body: " Body\n\n tail ", html: "<p>unused</p>", tags: ["swift"], assets: [try testAssetFile().path]),
            execution: .init(taskID: task, platform: .simFixture), command: .prepare, onEvent: { _ in })
        if defect == "valid" { #expect(result == .readyForReview(message: "模拟平台已填好")) }
        else if defect == "writeFailure" {
            #expect(result.failure?.code == .operationResultUnknown)
            let log = try String(contentsOf: directory.appendingPathComponent("log"))
            #expect(!log.contains("await page.setInputFiles"))
            #expect(!log.contains("#tags"))
        } else { #expect(result.failure?.code == .verificationFailed) }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["INKPOST_BROWSER_TESTS"] == "1"))
    func realFixtureAdapterBrowserSmoke() async throws {
        let image = FileManager.default.temporaryDirectory.appendingPathComponent("fixture-\(UUID().uuidString).png")
        try Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!.write(to: image)
        let service = DispatchService(registryFactory: { .init([FixtureChannelAdapter()]) })
        let task = UUID(); try await service.beginTask(id: task)
        let result = try await service.execute(request: .init(title: "Fixture smoke", body: "Complete body", tags: ["swift"], assets: [image.path]),
            execution: .init(taskID: task, platform: .simFixture), command: .prepare, onEvent: { _ in })
        #expect(result == .readyForReview(message: "模拟平台已填好"))
        let id = try #require(service.workspaceID)
        let engine = try EgoLiteEngine()
        let check = try await engine.runRaw(script: "const task = await taskSpace(\(id)); const page = task.page('p1'); cliLog(JSON.stringify({unpublished: await page.evaluate(() => !document.querySelector('#receipt').dataset.url)}));")
        #expect(check.bool("unpublished") == true)
        if result.failure == nil {
            _ = try await engine.runRaw(script: "const task = await taskSpace(\(id)); await task.finish({keep:[]}); cliLog(JSON.stringify({ok:true}));")
        }
    }
}
