import Foundation
import AppKit
import Testing
@testable import PublishKit

@MainActor
struct XChannelAdapterTests {
    @Test func plainTextCompositionDoesNotMutateRequest() {
        let request = ChannelRequest(title: " Title ", body: " Body\n\n   #AI\t##工具\n #中文  ", html: " <p>unused</p> ")
        let original = request
        #expect(XChannelAdapter().expectedBody(for: request) == " Title \n Body\n\n   #AI\t##工具\n #中文  ")
        #expect(request == original)
    }

    @Test func compositionAndLimitsPreserveInput() throws {
        let adapter = XChannelAdapter()

        #expect(adapter.expectedBody(for: .init(title: " 标题 ", body: " 正文\n\n  尾 ")) == " 标题 \n 正文\n\n  尾 ")
        #expect(adapter.expectedBody(for: .init(title: "", body: "正文")) == "正文")
        try adapter.validate(.init(title: "", body: String(repeating: "中", count: 1899), assets: ["1","2","3","4"]))
        #expect(throws: ChannelFailure.self) { try adapter.validate(.init(title: "题", body: String(repeating: "中", count: 1898))) }
        #expect(throws: ChannelFailure.self) { try adapter.validate(.init(title: "", body: "正文", assets: ["1","2","3","4","5"])) }
        #expect(throws: ChannelFailure.self) { try adapter.validate(.init(title: "题", body: " \n")) }
        try adapter.validate(.init(title: "", body: String(repeating: "🖋️", count: 1899)))
    }

    @Test(arguments: ["retry", "retryLogin", "resetFailed", "valid", "login", "conflict", "rejected", "cancel"])
    func realAdapterUsesNativePasteAndChecksResult(_ mode: String) async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let binary = dir.appendingPathComponent("x-stub")
        let log = dir.appendingPathComponent("log")
        let request = ChannelRequest(title: "标题", body: " 正文\n\n尾 ")
        let expected = XChannelAdapter().expectedBody(for: request)
        let source = """
        #!/usr/bin/python3
        import json,sys,pathlib
        root=pathlib.Path(__file__).parent
        script=sys.stdin.read()
        with (root/'log').open('a') as f:f.write(script+'\\n')
        path=root/'state'
        mode=\(String(reflecting: mode))
        state=json.loads(path.read_text()) if path.exists() else {'body':'old draft' if mode in ['retry','retryLogin','resetFailed'] else '','opens':0}
        result={'ok':True}
        if 'x:open-editor' in script:
            state['opens']+=1
            result['loginRequired']=mode in ['login','retryLogin'] and state['opens']==1
        if 'x:clear-editor' in script and mode!='resetFailed':state['body']=''
        if 'x:paste-body' in script:state['body']=\(String(reflecting: expected))
        if 'x:read-page' in script:result['value']={'body':'other' if mode=='conflict' else state['body'],'images':[],'busy':False,'rejected':mode=='rejected','accepted':True}
        path.write_text(json.dumps(state))
        print(json.dumps(result))
        """
        try source.write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
        let bridge = try EgoBridge(spaceName: "x-stub", engine: EgoLiteEngine(binaryPath: binary.path))
        let adapter = XChannelAdapter()
        func execute(_ command: ChannelCommand) async throws -> ChannelOutcome {
            let context = ChannelExecutionContext(execution: .init(taskID: UUID(), platform: .x), command: command,
                bridge: bridge, onEvent: { _ in })
            return try await adapter.execute(request: request, context: context)
        }
        if mode == "cancel" {
            let task = Task { try await execute(.prepare) }; task.cancel()
            do { _ = try await task.value; Issue.record("Cancellation swallowed") } catch { #expect(error is CancellationError) }
            return
        }
        if mode == "resetFailed" {
            do { _ = try await execute(.retry); Issue.record("Pasted before clearing") }
            catch { #expect((error as? ChannelFailure)?.recovery == .inspectionRequired) }
            #expect(!(try String(contentsOf: log)).contains("x:paste-body"))
            return
        }
        if ["conflict", "rejected"].contains(mode) {
            do { _ = try await execute(.prepare); Issue.record("Invalid content accepted") } catch { #expect(error is ChannelFailure) }
            #expect(!(try String(contentsOf: log)).contains("x:paste-body"))
        } else {
            var outcome = try await execute(mode.hasPrefix("retry") ? .retry : .prepare)
            if ["login", "retryLogin"].contains(mode) { #expect(outcome.failure?.code == .loginRequired); outcome = try await execute(.resumeAfterUser) }
            #expect(outcome.failure == nil)
            _ = try await execute(.resumeAfterUser)
            let scripts = try String(contentsOf: log)
            let executions = mode == "closedPanel" ? 1 : 2
            #expect(scripts.components(separatedBy: "x:clear-editor").count - 1 == executions)
            #expect(scripts.components(separatedBy: "x:paste-body").count - 1 == executions)
            for paste in scripts.components(separatedBy: "// x:paste-body").dropFirst() {
                let operation = paste.components(separatedBy: "cliLog")[0]
                #expect(!operation.contains("await page.click"))
                #expect(operation.contains("document.activeElement"))
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["INKPOST_X_LIVE"] == "1"))
    func liveXEditorContractWithoutWriting() async throws {
        let bridge = try EgoBridge(spaceName: try #require(ProcessInfo.processInfo.environment["INKPOST_X_LIVE_SPACE"]), engine: EgoLiteEngine(), pageLabel: try #require(ProcessInfo.processInfo.environment["INKPOST_X_LIVE_PAGE"]))
        let raw = try await bridge.run("""
            const value = await page.evaluate(() => {
                const editors = document.querySelectorAll('[role="dialog"] textarea');
                const root = editors[0]?.closest('[role="dialog"]');
                return {uniqueEditor:editors.length === 1 && editors[0].checkVisibility(),
                    uniqueSubmit:root && [...root.querySelectorAll('form button')].filter(button =>
                        button.checkVisibility() && /^(发帖|Post)$/.test(button.textContent.trim())).length === 1};
            });
            cliLog(JSON.stringify({ok:true,value}));
            """)
        struct Result: Decodable {
            struct Contract: Decodable { let uniqueEditor: Bool; let uniqueSubmit: Bool }
            let value: Contract
        }
        let contract = try JSONDecoder().decode(Result.self, from: Data(raw.utf8)).value
        #expect(contract.uniqueEditor)
        #expect(contract.uniqueSubmit)
    }
}

@MainActor
struct XImageTests {
    @Test(arguments: ["valid", "unknown", "timeout", "reordered", "deleted", "replaced"])
    func uploadCheckpointsPreventDuplicates(_ mode: String) async throws {
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
        if 'x:open-editor' in script:result['loginRequired']=False
        if 'x:check-quick-publish' in script:result['present']=True
        if 'x:clear-editor' in script:state['body']='';state['images']=[];state['reverse']=False
        if 'x:paste-body' in script:state['body']='unused\\nBody'
        if 'x:paste-image' in script:
            state['uploads']+=1
            if mode=='unknown':result={'ok':False,'error':'write result unknown'}
            else:state['images'].append({'identity':str(state['uploads']), 'ready':True})
        if 'x:wait-images' in script:
            if mode=='timeout':result={'ok':False,'error':'upload timeout'}
        if 'x:read-page' in script:result['value']={'body':state['body'],'images':list(reversed(state['images'])) if state['reverse'] else state['images'],'accepted':True,'rejected':False,'busy':False}
        path.write_text(json.dumps(state))
        print(json.dumps(result))
        """
        try source.write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
        let bridge = try EgoBridge(spaceName: "image-stub", engine: EgoLiteEngine(binaryPath: binary.path))
        let adapter = XChannelAdapter()
        let request = ChannelRequest(title: "unused", body: "Body", html: "unused", assets: [original.path, original.path])
        let prepared = try AssetService.preparePNGAssets(request.assets)
        func run(_ command: ChannelCommand) async throws -> ChannelOutcome {
            try await adapter.execute(request: request, context: .init(execution: .init(taskID: UUID(), platform: .x), command: command, bridge: bridge, preparedAssets: prepared.assets, onEvent: { _ in }))
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
            } else { #expect(try await run(.resumeAfterUser).failure == nil) }
        } else {
            do { _ = try await run(.prepare); Issue.record("Upload failure swallowed") }
            catch { #expect(!(error is CancellationError)) }
            do { _ = try await run(.resumeAfterUser); Issue.record("Uncertain upload replayed") }
            catch {
                #expect(error is EgoBridge.BridgeError)
            }
        }
        let log = try String(contentsOf: directory.appendingPathComponent("log"))
        #expect(log.components(separatedBy: "x:paste-image").count - 1 == (["valid","reordered","deleted","replaced"].contains(mode) ? 4 : 2))
        #expect(!log.contains("page.reload"))
        #expect(try Data(contentsOf: original) == sourceBytes)
        #expect(prepared.assets.allSatisfy { $0.pngPath.hasSuffix(".png") && $0.pngPath != original.path })
    }
}
