import Foundation
import AppKit
import Testing
@testable import PublishKit

@MainActor
struct BonjourChannelAdapterTests {
    @Test func completeInputAndWhitespaceArePreserved() throws {
        let adapter = BonjourChannelAdapter()
        let request = ChannelRequest(title: " 标题 ", body: "  正文🧪\n\n  #AI\t尾  ", html: " <p>unused</p> ", assets: ["a", "b"])
        let original = request
        #expect(adapter.expectedBody(for: request) == " 标题 \n" + request.body)
        #expect(adapter.expectedBody(for: .init(title: "", body: request.body)) == request.body)
        #expect(adapter.expectedBody(for: .init(title: " ", body: "正文")) == " \n正文")
        #expect(adapter.capabilities.usesTitle)
        try adapter.validate(request)
        #expect(request == original)
        #expect(ChannelRegistry.standard.adapter(for: .bonjour) != nil)
        #expect(throws: ChannelFailure.self) { try adapter.validate(.init(title: "题", body: " \n")) }
        // No invented account limit: actual editor acceptance decides long input support.
        try adapter.validate(.init(title: "", body: String(repeating: "中", count: 5000)))
        #expect(throws: ChannelFailure.self) { try adapter.validate(.init(title: "", body: String(repeating: "中", count: 5001))) }
        #expect(throws: ChannelFailure.self) { try adapter.validate(.init(title: "", body: String(repeating: "🧪", count: 2501))) }
    }

    @Test(arguments: ["retry", "retryLogin", "resetFailed", "valid", "login", "conflict", "rejected", "cancel", "unknownBody", "closedPanel", "testDraft"])
    func realAdapterUsesNativePasteAndChecksResult(_ mode: String) async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let binary = dir.appendingPathComponent("bonjour-stub")
        let log = dir.appendingPathComponent("log")
        let request = ChannelRequest(title: "标题", body: " 正文\n\n尾 ")
        let expected = BonjourChannelAdapter().expectedBody(for: request)
        let source = """
        #!/usr/bin/python3
        import json,sys,pathlib,subprocess
        root=pathlib.Path(__file__).parent
        script=sys.stdin.read()
        with (root/'log').open('a') as f:f.write(script+'\\n')
        path=root/'state'
        mode=\(String(reflecting: mode))
        state=json.loads(path.read_text()) if path.exists() else {'body':'old draft' if mode in ['retry','retryLogin','resetFailed','testDraft'] else '','images':([{'identity':'blob:test-blue','ready':True},{'identity':'blob:test-orange','ready':True}] if mode=='testDraft' else []),'opens':0}
        result={'ok':True}
        if 'bonjour:open-editor' in script:
            state['opens']+=1
            result['loginRequired']=mode in ['login','retryLogin'] and state['opens']==1
        if 'bonjour:check-quick-publish' in script:result['present']=not(mode=='closedPanel' and state['opens']>1)
        if 'bonjour:reset-editor' in script and mode!='resetFailed':state['body']='';state['images']=[]
        if 'bonjour:paste-body' in script:
            if mode=='unknownBody':result={'ok':False,'error':'paste result unknown'}
            else:state['body']=subprocess.check_output(['/usr/bin/pbpaste']).decode('utf-8')
        if 'bonjour:read-page' in script:result['value']={'body':'other' if mode=='conflict' else state['body'],'images':state['images'],'busy':False,'rejected':mode=='rejected','accepted':True}
        path.write_text(json.dumps(state))
        print(json.dumps(result))
        """
        try source.write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
        let bridge = try EgoBridge(spaceName: "bonjour-stub", engine: EgoLiteEngine(binaryPath: binary.path))
        let adapter = BonjourChannelAdapter()
        func execute(_ command: ChannelCommand, input: ChannelRequest? = nil) async throws -> ChannelOutcome {
            let context = ChannelExecutionContext(execution: .init(taskID: UUID(), platform: .bonjour), command: command,
                bridge: bridge, onEvent: { _ in })
            return try await adapter.execute(request: input ?? request, context: context)
        }
        if mode == "cancel" {
            let task = Task { try await execute(.prepare) }; task.cancel()
            do { _ = try await task.value; Issue.record("Cancellation swallowed") } catch { #expect(error is CancellationError) }
            return
        }
        if mode == "resetFailed" {
            do { _ = try await execute(.retry); Issue.record("Pasted before clearing") }
            catch { #expect((error as? ChannelFailure)?.recovery == .inspectionRequired) }
            #expect(!(try String(contentsOf: log)).contains("bonjour:paste-body"))
            return
        }
        if mode == "unknownBody" {
            for command in [ChannelCommand.prepare, .resumeAfterUser] {
                do { _ = try await execute(command); Issue.record("Uncertain body write accepted") }
                catch { #expect((error as? ChannelFailure)?.recovery == .inspectionRequired) }
            }
            #expect(try String(contentsOf: log).components(separatedBy: "bonjour:paste-body").count - 1 == 2)
        } else if ["conflict", "rejected"].contains(mode) {
            do { _ = try await execute(.prepare); Issue.record("Invalid content accepted") }
            catch {
                let failure = try #require(error as? ChannelFailure)
                #expect(failure.stage == .fillingContent)
                if mode == "conflict" {
                    #expect(failure.recovery == .inspectionRequired)
                    #expect(failure.detail.contains("页面未清空"))
                }
            }
            #expect(!(try String(contentsOf: log)).contains("bonjour:paste-body"))
            #expect(!(try String(contentsOf: log)).contains("bonjour:paste-image"))
        } else {
            var outcome = try await execute(mode.hasPrefix("retry") ? .retry : .prepare)
            if ["login", "retryLogin"].contains(mode) { #expect(outcome.failure?.code == .loginRequired); outcome = try await execute(.resumeAfterUser) }
            #expect(outcome.failure == nil)
            if mode == "closedPanel" {
                do { _ = try await execute(.resumeAfterUser); Issue.record("Closed composer accepted") }
                catch {
                    #expect((error as? ChannelFailure)?.code == .editorUnavailable)
                    #expect((error as? ChannelFailure)?.recovery == .inspectionRequired)
                }
            } else { _ = try await execute(.resumeAfterUser) }
            let scripts = try String(contentsOf: log)
            let attempts = mode == "closedPanel" ? 1 : 2
            #expect(scripts.components(separatedBy: "bonjour:reset-editor").count - 1 == attempts)
            if mode == "testDraft" {
                #expect(scripts.contains("index < 2"))
                let state = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("state"))) as! [String: Any]
                #expect(state["body"] as? String == expected)
                #expect((state["images"] as? [Any])?.isEmpty == true)
                let next = ChannelRequest(title: "下一次任务", body: "本次用户内容，不使用旧稿")
                #expect(try await execute(.prepare, input: next).failure == nil)
                let nextState = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("state"))) as! [String: Any]
                #expect(nextState["body"] as? String == adapter.expectedBody(for: next))
                #expect((nextState["images"] as? [Any])?.isEmpty == true)
            }
            #expect(scripts.components(separatedBy: "bonjour:paste-body").count - 1 == attempts)
            #expect(scripts.components(separatedBy: "bonjour:open-quick-publish").count - 1 == 1)
            #expect(scripts.contains("[data-community-post-composer-dialog] textarea"))
            #expect(scripts.contains("document.activeElement === editors[0]"))
            #expect(!scripts.contains("page.reload"))
            #expect(!scripts.contains("page.click(\"text=发送"))
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["INKPOST_BONJOUR_LIVE"] == "1"))
    func liveBonjourEditorContractWithoutWriting() async throws {
        // A real-account draft persists across Pages. Never fill or reset it in automated tests.
        let bridge = try EgoBridge(spaceName: try #require(ProcessInfo.processInfo.environment["INKPOST_BONJOUR_LIVE_SPACE"]), engine: EgoLiteEngine(), pageLabel: try #require(ProcessInfo.processInfo.environment["INKPOST_BONJOUR_LIVE_PAGE"]))
        let result = try await bridge.run("""
            const value = await page.evaluate(() => {
                const roots = document.querySelectorAll('[data-community-post-composer-dialog]');
                const root = roots[0];
                const editors = root?.querySelectorAll('textarea[data-community-post-composer-input]');
                return {
                    uniqueEditor: roots.length === 1 && editors?.length === 1,
                    maximumLength: editors?.[0]?.maxLength ?? -1,
                    uniqueSubmit: root?.querySelectorAll('button[type="submit"][aria-label="发布"]').length === 1
                };
            });
            cliLog(JSON.stringify({ok:true,value}));
            """)
        struct Result: Decodable {
            struct Contract: Decodable { let uniqueEditor: Bool; let maximumLength: Int; let uniqueSubmit: Bool }
            let value: Contract
        }
        let contract = try JSONDecoder().decode(Result.self, from: Data(result.utf8)).value
        #expect(contract.uniqueEditor)
        #expect(contract.maximumLength == 5000)
        #expect(contract.uniqueSubmit)
    }
}

@MainActor
struct BonjourImageTests {
    @Test(arguments: ["valid", "unknown", "timeout", "reordered", "deleted", "replaced"])
    func eachExecutionClearsAttachmentsBeforeRefilling(_ mode: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let binary = directory.appendingPathComponent("image-stub")
        let original = directory.appendingPathComponent("source.tiff")
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let sourceBytes = try #require(bitmap.tiffRepresentation)
        try sourceBytes.write(to: original)
        let source = """
        #!/usr/bin/python3
        import json,sys,pathlib
        root=pathlib.Path(__file__).parent
        script=sys.stdin.read()
        with (root/'log').open('a') as f:f.write(script+'\\n')
        path=root/'state'
        state=json.loads(path.read_text()) if path.exists() else {'body':'','images':[],'uploads':0,'reverse':False}
        mode=\(String(reflecting: mode))
        result={'ok':True}
        if 'bonjour:open-editor' in script:result['loginRequired']=False
        if 'bonjour:check-quick-publish' in script:result['present']=True
        if 'bonjour:reset-editor' in script:state['body']='';state['images']=[];state['reverse']=False
        if 'bonjour:paste-body' in script:state['body']='unused\\nBody'
        if 'bonjour:paste-image' in script:
            state['uploads']+=1
            if mode=='unknown':result={'ok':False,'error':'write result unknown'}
            else:state['images'].append({'identity':str(state['uploads']), 'ready':True})
        if 'bonjour:wait-images' in script:
            if mode=='timeout':result={'ok':False,'error':'upload timeout'}
        if 'bonjour:read-page' in script:result['value']={'body':state['body'],'images':list(reversed(state['images'])) if state['reverse'] else state['images'],'accepted':True,'rejected':False,'busy':False}
        path.write_text(json.dumps(state))
        print(json.dumps(result))
        """
        try source.write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
        let bridge = try EgoBridge(spaceName: "image-stub", engine: EgoLiteEngine(binaryPath: binary.path))
        let adapter = BonjourChannelAdapter()
        let request = ChannelRequest(title: "unused", body: "Body", html: "unused", assets: [original.path, original.path])
        let prepared = try AssetService.preparePNGAssets(request.assets)
        func run(_ command: ChannelCommand) async throws -> ChannelOutcome {
            try await adapter.execute(request: request, context: .init(execution: .init(taskID: UUID(), platform: .bonjour), command: command, bridge: bridge, preparedAssets: prepared.assets, onEvent: { _ in }))
        }
        if ["valid", "reordered", "deleted", "replaced"].contains(mode) {
            #expect(try await run(.prepare).failure == nil)
            if ["reordered", "deleted", "replaced"].contains(mode) {
                let path = directory.appendingPathComponent("state")
                var state = try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as! [String: Any]
                if mode == "reordered" { state["reverse"] = true }
                if mode == "deleted" { state["images"] = [] }
                if mode == "replaced" { state["images"] = [["identity": "replacement", "ready": true], ["identity": "2", "ready": true]] }
                try JSONSerialization.data(withJSONObject: state).write(to: path)
                #expect(try await run(.resumeAfterUser).failure == nil)
                let refreshed = try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as! [String: Any]
                let images = refreshed["images"] as! [[String: Any]]
                #expect(images.compactMap { $0["identity"] as? String } == ["3", "4"])
            } else {
                #expect(try await run(.resumeAfterUser).failure == nil)
                #expect(try await run(.retry).failure == nil)
                #expect(try await run(.resumeAfterUser).failure == nil)
            }
        } else {
            do { _ = try await run(.prepare); Issue.record("Upload failure swallowed") }
            catch { #expect(!(error is CancellationError)) }
            do { _ = try await run(.resumeAfterUser); Issue.record("Upload failure swallowed after reset") }
            catch { #expect((error as? ChannelFailure)?.recovery == .inspectionRequired) }
        }
        let log = try String(contentsOf: directory.appendingPathComponent("log"))
        #expect(log.components(separatedBy: "bonjour:paste-image").count - 1 == (mode == "valid" ? 8 : ["reordered","deleted","replaced"].contains(mode) ? 4 : 2))
        #expect(!log.contains("page.reload"))
        #expect(try Data(contentsOf: original) == sourceBytes)
        #expect(prepared.assets.allSatisfy { $0.pngPath.hasSuffix(".png") && $0.pngPath != original.path })
    }
}
