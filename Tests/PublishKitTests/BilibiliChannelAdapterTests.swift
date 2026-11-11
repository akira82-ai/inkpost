import Foundation
import Testing
@testable import PublishKit

@MainActor
struct BilibiliChannelAdapterTests {
    @Test func rawInputAndTitleLimit() throws {
        let adapter = BilibiliChannelAdapter()
        let request = ChannelRequest(title: " 标题 ", body: "  正文🧪\n\n#AI\t尾  \n", html: "<p>unused</p>")
        let original = request
        try adapter.validate(request)
        try adapter.check(.init(title: request.title, body: request.body, images: [], accepted: true, rejected: false), request: request)
        #expect(request == original)
        #expect(ChannelRegistry.standard.adapter(for: .bilibili) != nil)
        #expect(PlatformID.bilibili.entryURL == "https://t.bilibili.com/")
        try adapter.validate(.init(title: String(repeating: "中", count: 20), body: "正文"))
        try adapter.validate(.init(title: String(repeating: "🧪", count: 10), body: "正文"))
        #expect(throws: ChannelFailure.self) { try adapter.validate(.init(title: String(repeating: "🧪", count: 11), body: "正文")) }
        #expect(throws: ChannelFailure.self) { try adapter.validate(.init(title: "", body: " \n")) }
        // Website trimming is an error, not a reason to weaken comparison.
        #expect(throws: ChannelFailure.self) {
            try adapter.check(.init(title: request.title, body: request.body.trimmingCharacters(in: .whitespacesAndNewlines), images: [], accepted: true, rejected: false), request: request)
        }
    }

    @Test(arguments: ["valid", "login", "oldDraft", "clearFailed", "changedBody", "changedTitle", "unknownTitle", "unknownBody", "unknownImage", "timeout", "reordered", "deleted", "replaced", "rejected", "blocked", "cancel", "cancelDuring"])
    func actualAdapterPreservesPageAndDoesNotReplayWrites(_ mode: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let binary = directory.appendingPathComponent("bilibili-stub")
        let request = ChannelRequest(title: "标题", body: "正文\n\nemoji 😀", html: "unused",
            assets: [try testAssetFile().path, try testAssetFile().path])
        let prepared = try AssetService.preparePNGAssets(request.assets)
        let source = """
        #!/usr/bin/python3
        import json,sys,pathlib
        root=pathlib.Path(__file__).parent
        script=sys.stdin.read()
        with (root/'log').open('a') as f:f.write(script+'\\n')
        path=root/'state'
        mode=\(String(reflecting: mode))
        state=json.loads(path.read_text()) if path.exists() else {'title':'old title' if mode in ['oldDraft','clearFailed'] else '','body':'user draft' if mode in ['oldDraft','clearFailed'] else '','images':[{'identity':'old','ready':True}] if mode=='oldDraft' else [],'opens':0,'uploads':0,'mutate':False}
        result={'ok':True}
        if 'bilibili:open-editor' in script:
            state['opens']+=1
            result['loginRequired']=mode=='login' and state['opens']==1
        if 'bilibili:clear-draft' in script:
            if mode!='clearFailed':state.update(title='',body='',images=[])
        if 'bilibili:paste-title' in script:
            assert 'page.click' in script and 'keyboard.paste' in script
            state['title']='' if mode=='unknownTitle' else \(String(reflecting: request.title))
            if mode=='unknownTitle':result={'ok':False,'error':'unknown title'}
        if 'bilibili:paste-body' in script:
            assert 'page.click' in script and 'keyboard.paste' in script
            state['body']='' if mode=='unknownBody' else \(String(reflecting: request.body))
            if mode=='unknownBody':result={'ok':False,'error':'unknown body'}
        if 'bilibili:add-image' in script:
            upload=pathlib.Path(json.loads(script.split('chooser.setFiles(',1)[1].split(');',1)[0]))
            assert upload.suffix=='.png' and upload.read_bytes().startswith(bytes([137,80,78,71,13,10,26,10]))
            state['uploads']+=1
            if mode=='unknownImage':result={'ok':False,'error':'unknown image'}
            else:state['images'].append({'identity':str(state['uploads']),'ready':True})
        if 'bilibili:wait-images' in script and mode=='timeout':result={'ok':False,'error':'timeout'}
        if 'bilibili:read-page' in script:
            title=state['title'];body=state['body'];images=state['images'][:]
            if state['mutate']:
                if mode=='changedBody':body='user edit'
                if mode=='changedTitle':title='user title'
                if mode=='reordered':images.reverse()
                if mode=='deleted':images=images[:1]
                if mode=='replaced':images[0]={'identity':'replacement','ready':True}
            result['value']={'title':title,'body':body,'images':images,'accepted':mode!='blocked','rejected':mode=='rejected'}
        path.write_text(json.dumps(state))
        print(json.dumps(result))
        """
        try source.write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
        let bridge = try EgoBridge(spaceName: "bilibili-stub", engine: EgoLiteEngine(binaryPath: binary.path))
        let adapter = BilibiliChannelAdapter(), id = UUID()
        func execute(_ command: ChannelCommand) async throws -> ChannelOutcome {
            try await adapter.execute(request: request, context: .init(execution: .init(taskID: id, platform: .bilibili),
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
                #expect(log.components(separatedBy: "bilibili:add-image").count - 1 == 1)
            }
            return
        }
        if ["clearFailed", "unknownTitle", "unknownBody", "unknownImage", "timeout", "rejected"].contains(mode) {
            do { _ = try await execute(.prepare); Issue.record("Failure accepted") }
            catch { #expect(error is ChannelFailure) }
            if !["rejected"].contains(mode) {
                do { _ = try await execute(.resumeAfterUser); Issue.record("Uncertain write replayed") }
                catch { #expect((error as? ChannelFailure)?.recovery == .inspectionRequired) }
            }
        } else {
            var outcome = try await execute(.prepare)
            if mode == "login" {
                #expect(outcome.failure?.code == .loginRequired)
                #expect(!(try String(contentsOf: directory.appendingPathComponent("log"))).contains("bilibili:paste-"))
                outcome = try await execute(.resumeAfterUser)
            }
            if mode == "blocked" { #expect(outcome.canResume) }
            else { #expect(outcome.failure == nil) }
            let path = directory.appendingPathComponent("state")
            var state = try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as! [String: Any]
            state["mutate"] = true
            try JSONSerialization.data(withJSONObject: state).write(to: path)
            if ["changedBody", "changedTitle", "reordered", "deleted", "replaced"].contains(mode) {
                do { _ = try await execute(.resumeAfterUser); Issue.record("User edits overwritten") }
                catch { #expect((error as? ChannelFailure)?.recovery == .inspectionRequired) }
            } else { _ = try await execute(.resumeAfterUser) }
        }
        let log = try String(contentsOf: directory.appendingPathComponent("log"))
        #expect(log.components(separatedBy: "bilibili:paste-title").count - 1 == (["clearFailed", "rejected"].contains(mode) ? 0 : 1))
        #expect(log.components(separatedBy: "bilibili:paste-body").count - 1 == (["clearFailed", "rejected", "unknownTitle"].contains(mode) ? 0 : 1))
        #expect(log.components(separatedBy: "bilibili:clear-draft").count - 1 == 1)
        #expect(!log.contains("page.reload"))
        #expect(!log.contains("page.click('.bili-dyn-publishing__action"))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["INKPOST_BILIBILI_LIVE"] == "1"))
    func liveDynamicWithoutPublishing() async throws {
        let name = try #require(ProcessInfo.processInfo.environment["INKPOST_BILIBILI_SPACE"])
        let bridge = try EgoBridge(spaceName: name, engine: EgoLiteEngine(), pageLabel: "p1")
        // This agent-created Page contains only our disposable test draft.
        for request in [ChannelRequest(title: "", body: "墨驿 B站验证 🧪\n换行\n\n空行 😀"),
                        ChannelRequest(title: "墨驿填写验证", body: "正文\n\n两张纯色测试图，不发布。", assets: ["/tmp/inkpost-bili-test-1.png", "/tmp/inkpost-bili-test-2.png"]),
                        ChannelRequest(title: "", body: "  首尾空白验证  ")] {
            _ = try await bridge.run("""
                await page.waitForSelector('.bili-rich-textarea__inner', {state:'visible'});
                const count = await page.evaluate(() => document.querySelectorAll('.bili-pics-uploader__item__remove').length);
                for (let i = 0; i < count; i++) {
                  await page.hover('.bili-pics-uploader__item >> nth=0', {label:'显示测试附件删除入口'});
                  await page.click('.bili-pics-uploader__item__remove >> nth=0', {label:'清理测试附件'});
                  await page.waitForFunction(expected => document.querySelectorAll('.bili-pics-uploader__item').length === expected, count - i - 1, {timeout:5000});
                }
                await page.click('.bili-dyn-publishing__title__input', {label:'清理测试标题'});
                await page.press('.bili-dyn-publishing__title__input', 'Meta+A');
                await page.keyboard.press('Backspace');
                await page.click('.bili-rich-textarea__inner', {label:'清理测试正文'});
                await page.press('.bili-rich-textarea__inner', 'Meta+A');
                await page.keyboard.press('Backspace');
                cliLog(JSON.stringify({ok:true}));
                """)
            let adapter = BilibiliChannelAdapter()
            let prepared = try AssetService.preparePNGAssets(request.assets)
            let id = UUID()
            for command in [ChannelCommand.prepare, .resumeAfterUser] {
                let context = ChannelExecutionContext(execution: .init(taskID: id, platform: .bilibili),
                    command: command, bridge: bridge, preparedAssets: prepared.assets, onEvent: { _ in })
                if request.body.hasPrefix("  ") {
                    do { _ = try await adapter.execute(request: request, context: context); Issue.record("Website trimming accepted") }
                    catch { #expect((error as? ChannelFailure)?.code == .verificationFailed) }
                } else {
                    let outcome = try await adapter.execute(request: request, context: context)
                    #expect(outcome.failure == nil)
                }
            }
        }
    }
}
