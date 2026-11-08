import Foundation
import Testing
@testable import PublishKit

@MainActor
struct JuejinChannelAdapterTests {
    @Test func rawCompositionAndNativeLimits() throws {
        let adapter = JuejinChannelAdapter()
        let request = ChannelRequest(title: " 标题 ", body: "  正文🧪\n\n#AI\t尾  \n", html: "<p>unused</p>", assets: ["a", "b"])
        let original = request
        #expect(adapter.expectedBody(for: request) == request.title + "\n" + request.body)
        #expect(adapter.expectedBody(for: .init(title: "", body: request.body)) == request.body)
        try adapter.validate(request)
        #expect(request == original)
        #expect(ChannelRegistry.standard.adapter(for: .juejin) != nil)
        try adapter.validate(.init(title: "", body: String(repeating: "中", count: 1000)))
        try adapter.validate(.init(title: "", body: String(repeating: "🧪", count: 500)))
        #expect(throws: ChannelFailure.self) { try adapter.validate(.init(title: "题", body: String(repeating: "中", count: 1000))) }
        #expect(throws: ChannelFailure.self) { try adapter.validate(.init(title: "", body: String(repeating: "🧪", count: 501))) }
        #expect(throws: ChannelFailure.self) { try adapter.validate(.init(title: "题", body: " \n")) }
    }

    @Test(arguments: ["valid", "login", "changedBody", "unknownBody", "unknownImage", "timeout", "reordered", "deleted", "replaced", "linkAdded", "rejected", "blocked", "cancel", "cancelDuring"])
    func realAdapterClearsOnceAndPreservesRecovery(_ mode: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let binary = directory.appendingPathComponent("juejin-stub")
        let first = try testAssetFile()
        let second = try testAssetFile()
        let request = ChannelRequest(title: "题", body: " 正文\n\n #AI 尾 ", html: "unused", assets: [first.path, second.path])
        let prepared = try AssetService.preparePNGAssets(request.assets)
        let expected = JuejinChannelAdapter().expectedBody(for: request)
        let source = """
        #!/usr/bin/python3
        import json,sys,pathlib
        root=pathlib.Path(__file__).parent
        script=sys.stdin.read()
        with (root/'log').open('a') as f:f.write(script+'\\n')
        path=root/'state'
        state=json.loads(path.read_text()) if path.exists() else {'body':'#新人报道#','images':[{'identity':'old','ready':True}],'opens':0,'uploads':0,'mutate':False,'links':1}
        mode=\(String(reflecting: mode))
        result={'ok':True}
        if 'juejin:open-editor' in script:
            state['opens']+=1
            result['loginRequired']=mode=='login' and state['opens']==1
        if 'juejin:replace-body' in script:
            assert 'Meta+A' in script and 'keyboard.insertText' in script and '.preview-image .delete' in script
            state['images']=[]; state['links']=0
            state['body']='' if mode=='unknownBody' else \(String(reflecting: expected))
            if mode=='unknownBody':result={'ok':False,'error':'unknown paste'}
        if 'juejin:add-image' in script:
            upload=pathlib.Path(json.loads(script.split("input#photo[type=file]', ",1)[1].split(');',1)[0]))
            assert upload.suffix=='.png' and upload.read_bytes().startswith(bytes([137,80,78,71,13,10,26,10]))
            state['uploads']+=1
            if mode=='unknownImage':result={'ok':False,'error':'unknown image'}
            else:state['images'].append({'identity':str(state['uploads']),'ready':True})
        if 'juejin:wait-images' in script and mode=='timeout':result={'ok':False,'error':'timeout'}
        if 'juejin:read-page' in script:
            body=state['body']; images=state['images'][:]
            if state['mutate']:
                if mode=='changedBody':body='user edit'
                if mode=='reordered':images.reverse()
                if mode=='deleted':images=images[:1]
                if mode=='replaced':images[0]={'identity':'replacement','ready':True}
            result['value']={'body':body,'images':images,'linkCount':1 if state['mutate'] and mode=='linkAdded' else state['links'],'accepted':mode!='blocked','rejected':mode=='rejected'}
        path.write_text(json.dumps(state))
        print(json.dumps(result))
        """
        try source.write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
        let bridge = try EgoBridge(spaceName: "juejin-stub", engine: EgoLiteEngine(binaryPath: binary.path))
        let adapter = JuejinChannelAdapter()
        let taskID = UUID()
        func execute(_ command: ChannelCommand) async throws -> ChannelOutcome {
            try await adapter.execute(request: request, context: .init(execution: .init(taskID: taskID, platform: .juejin),
                command: command, bridge: bridge, preparedAssets: prepared.assets, onEvent: { event in
                    if mode == "cancelDuring", case .progress(_, let completed, _) = event.payload, completed == 1 {
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                }))
        }
        if ["cancel", "cancelDuring"].contains(mode) {
            let task = Task { try await execute(.prepare) }
            if mode == "cancel" { task.cancel() }
            do { _ = try await task.value; Issue.record("Cancellation swallowed") }
            catch { #expect(error is CancellationError) }
            if mode == "cancelDuring" {
                let log = try String(contentsOf: directory.appendingPathComponent("log"))
                #expect(log.components(separatedBy: "juejin:add-image").count - 1 == 1)
            }
            return
        }
        if ["unknownBody", "unknownImage", "timeout", "rejected"].contains(mode) {
            do { _ = try await execute(.prepare); Issue.record("Failure accepted") }
            catch { #expect(error is ChannelFailure) }
            if mode != "rejected" {
                do { _ = try await execute(.resumeAfterUser); Issue.record("Uncertain write replayed") }
                catch { #expect((error as? ChannelFailure)?.recovery == .inspectionRequired) }
            }
        } else {
            var outcome = try await execute(.prepare)
            if mode == "login" {
                #expect(outcome.failure?.code == .loginRequired)
                #expect(!(try String(contentsOf: directory.appendingPathComponent("log"))).contains("juejin:replace-body"))
                outcome = try await execute(.resumeAfterUser)
            }
            if mode == "blocked" { #expect(outcome.canResume) }
            else { #expect(outcome.failure == nil) }
            let path = directory.appendingPathComponent("state")
            var state = try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as! [String: Any]
            state["mutate"] = true
            try JSONSerialization.data(withJSONObject: state).write(to: path)
            if ["changedBody", "reordered", "deleted", "replaced", "linkAdded"].contains(mode) {
                do { _ = try await execute(.resumeAfterUser); Issue.record("User edits overwritten") }
                catch { #expect((error as? ChannelFailure)?.recovery == .inspectionRequired) }
            } else { _ = try await execute(.resumeAfterUser) }
        }
        let scripts = try String(contentsOf: directory.appendingPathComponent("log"))
        #expect(scripts.components(separatedBy: "juejin:replace-body").count - 1 == 1)
        let expectedImages = ["unknownBody", "rejected"].contains(mode) ? 0 : (["unknownImage", "timeout"].contains(mode) ? 1 : 2)
        #expect(scripts.components(separatedBy: "juejin:add-image").count - 1 == expectedImages)
        #expect(!scripts.contains("page.reload"))
        #expect(!scripts.contains("await page.click('text=发布'"))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["INKPOST_JUEJIN_LIVE"] == "1"))
    func livePinsWithoutPublishing() async throws {
        let space = try #require(ProcessInfo.processInfo.environment["INKPOST_JUEJIN_SPACE"])
        let bridge = try EgoBridge(spaceName: space, engine: EgoLiteEngine(), pageLabel: "p1")
        let requests = [
            ChannelRequest(title: "", body: "\n\n  **纯文本**\t#AI\n\n尾部 👨‍👩‍👧‍👦🖋️  \n\n"),
            ChannelRequest(title: "", body: "  单行空格 🧪  "),
            ChannelRequest(title: "墨驿验证 🧪", body: "  保留空格\n\n第二段 #普通标签#\nhttps://example.com\n仅填写，不发布。  \n",
                html: "<p>此字段不使用</p>", assets: ["/tmp/inkpost-juejin-probe-1.png", "/tmp/inkpost-juejin-probe-2.png"])
        ]
        for request in requests {
            let adapter = JuejinChannelAdapter()
            let prepared = try AssetService.preparePNGAssets(request.assets)
            let id = UUID()
            for command in [ChannelCommand.prepare, .resumeAfterUser] {
                let outcome = try await adapter.execute(request: request, context: .init(execution: .init(taskID: id, platform: .juejin),
                    command: command, bridge: bridge, preparedAssets: prepared.assets, onEvent: { _ in }))
                #expect(outcome.failure == nil)
            }
        }
    }
}
