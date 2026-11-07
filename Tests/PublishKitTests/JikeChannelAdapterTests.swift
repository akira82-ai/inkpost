import Foundation
import AppKit
import Testing
@testable import PublishKit

@MainActor
struct JikeChannelAdapterTests {
    @Test(arguments: ["valid", "login", "conflict", "rejected", "cancel"])
    func realAdapterUsesNativePasteAndChecksResult(_ mode: String) async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let binary = dir.appendingPathComponent("jike-stub")
        let log = dir.appendingPathComponent("log")
        let request = ChannelRequest(title: "标题", body: " 正文\n\n尾 ", tags: ["x"])
        let expected = JikeChannelAdapter().expectedBody(for: request)
        let source = """
        #!/usr/bin/python3
        import json,sys,pathlib
        root=pathlib.Path(__file__).parent
        script=sys.stdin.read()
        with (root/'log').open('a') as f:f.write(script+'\\n')
        path=root/'state'
        state=json.loads(path.read_text()) if path.exists() else {'body':'','opens':0}
        mode=\(String(reflecting: mode))
        result={'ok':True}
        if 'jike:open-editor' in script:
            state['opens']+=1
            result['loginRequired']=mode=='login' and state['opens']==1
        if 'jike:paste-body' in script:state['body']=\(String(reflecting: expected))
        if 'jike:read-page' in script:result['value']={'body':'other' if mode=='conflict' else state['body'],'images':[],'rejected':mode=='rejected','accepted':True}
        path.write_text(json.dumps(state))
        print(json.dumps(result))
        """
        try source.write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
        let bridge = try EgoBridge(spaceName: "jike-stub", engine: EgoLiteEngine(binaryPath: binary.path))
        let adapter = JikeChannelAdapter()
        func execute(_ command: ChannelCommand) async throws -> ChannelOutcome {
            let context = ChannelExecutionContext(execution: .init(taskID: UUID(), platform: .jike), command: command,
                bridge: bridge, onEvent: { _ in })
            return try await adapter.execute(request: request, context: context)
        }
        if mode == "cancel" {
            let task = Task { try await execute(.prepare) }; task.cancel()
            do { _ = try await task.value; Issue.record("Cancellation swallowed") } catch { #expect(error is CancellationError) }
            return
        }
        if ["conflict", "rejected"].contains(mode) {
            do { _ = try await execute(.prepare); Issue.record("Invalid content accepted") } catch { #expect(error is ChannelFailure) }
            #expect(!(try String(contentsOf: log)).contains("jike:paste-body"))
        } else {
            var outcome = try await execute(.prepare)
            if mode == "login" { #expect(outcome.failure?.code == .loginRequired); outcome = try await execute(.resumeAfterUser) }
            #expect(outcome.failure == nil)
            _ = try await execute(.resumeAfterUser)
            let scripts = try String(contentsOf: log)
            #expect(scripts.components(separatedBy: "jike:paste-body").count - 1 == 1)
            #expect(!scripts.contains("await page.click(\'form button"))
        }
    }

}

@MainActor
struct JikeInputTests {
    @Test func completeRequestAndValidation() throws {
        let adapter = JikeChannelAdapter()
        let request = ChannelRequest(title: "保留但不使用标题", body: " 正文\n\n 尾 ", html: "<p>unused</p>", tags: ["测试"], assets: ["a","b"])
        #expect(adapter.expectedBody(for: request) == " 正文\n\n 尾 \n\n#测试")
        try adapter.validate(request)
        #expect(throws: ChannelFailure.self) { try adapter.validate(.init(title: "标题", body: " \n")) }
        #expect(ChannelRegistry.standard.adapter(for: .jike) != nil)
        let state = JikeChannelAdapter.State(body: "正文", images: [], accepted: true, rejected: false)
        #expect(throws: ChannelFailure.self) { try adapter.check(state, request: request, allowEmpty: false) }
        #expect(throws: ChannelFailure.self) { try adapter.validateImages([.init(identity: "unexpected", ready: true)]) }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["INKPOST_JIKE_LIVE"] == "1"))
    func liveInlineComposerWithoutSending() async throws {
        let space = try #require(ProcessInfo.processInfo.environment["INKPOST_JIKE_SPACE"])
        let page = try #require(ProcessInfo.processInfo.environment["INKPOST_JIKE_PAGE"])
        let bridge = try EgoBridge(spaceName: space, engine: EgoLiteEngine(), pageLabel: page)
        let adapter = JikeChannelAdapter()
        let second = FileManager.default.temporaryDirectory.appendingPathComponent("jike-second-\(UUID().uuidString).png")
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 80, pixelsHigh: 80, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for y in 0..<80 { for x in 0..<80 { bitmap.setColor(NSColor(deviceRed: 0.9, green: 0.5, blue: 0.2, alpha: 1), atX: x, y: y) } }
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: second)
        let first = ProcessInfo.processInfo.environment["INKPOST_JIKE_ASSET"] ?? "/tmp/inkpost-jike-probe.png"
        let request = ChannelRequest(title: "此标题不应填入", body: "  即刻适配器验证\n\n保留空行与  空格。\n仅填写，不发送。  ", tags: ["验证"], assets: [first, second.path])
        let prepared = try AssetService.preparePNGAssets(request.assets)
        for command in [ChannelCommand.prepare, .resumeAfterUser] {
            let context = ChannelExecutionContext(execution: .init(taskID: UUID(), platform: .jike), command: command, bridge: bridge, preparedAssets: prepared.assets, onEvent: { _ in })
            let result = try await adapter.execute(request: request, context: context)
            #expect(result.failure == nil)
        }
    }
}

@MainActor
struct JikeImageTests {
    @Test(arguments: ["valid", "unknown", "timeout", "reordered"])
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
        if 'jike:open-editor' in script:result['loginRequired']=False
        if 'jike:paste-body' in script:state['body']='Body'
        if 'jike:upload-image' in script:
            upload=pathlib.Path(json.loads(script.split('await chooser.setFiles(',1)[1].split(');',1)[0]))
            assert upload.suffix == '.png' and upload != root/'source.tiff'
            assert upload.read_bytes().startswith(bytes([137,80,78,71,13,10,26,10]))
            with (root/'uploads').open('a') as f:f.write(str(upload)+'\\n')
            state['uploads']+=1
            if mode=='unknown':result={'ok':False,'error':'write result unknown'}
            else:state['images'].append({'identity':str(state['uploads']), 'ready':True})
        if 'jike:wait-images' in script:
            assert all(pathlib.Path(p).exists() for p in (root/'uploads').read_text().splitlines())
            if mode=='timeout':result={'ok':False,'error':'upload timeout'}
        if 'jike:read-page' in script:result['value']={'body':state['body'],'images':list(reversed(state['images'])) if state['reverse'] else state['images'],'accepted':True,'rejected':False}
        path.write_text(json.dumps(state))
        print(json.dumps(result))
        """
        try source.write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
        let bridge = try EgoBridge(spaceName: "image-stub", engine: EgoLiteEngine(binaryPath: binary.path))
        let adapter = JikeChannelAdapter()
        let request = ChannelRequest(title: "unused", body: "Body", html: "unused", assets: [original.path, original.path])
        let prepared = try AssetService.preparePNGAssets(request.assets)
        func run(_ command: ChannelCommand) async throws -> ChannelOutcome {
            try await adapter.execute(request: request, context: .init(execution: .init(taskID: UUID(), platform: .jike), command: command, bridge: bridge, preparedAssets: prepared.assets, onEvent: { _ in }))
        }
        if ["valid", "reordered"].contains(mode) {
            #expect(try await run(.prepare).failure == nil)
            if mode == "reordered" {
                let path = directory.appendingPathComponent("state")
                var state = try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as! [String: Any]
                state["reverse"] = true
                try JSONSerialization.data(withJSONObject: state).write(to: path)
                do { _ = try await run(.resumeAfterUser); Issue.record("Reordered images accepted") }
                catch { #expect((error as? ChannelFailure)?.recovery == .inspectionRequired) }
            } else { #expect(try await run(.resumeAfterUser).failure == nil) }
        } else {
            do { _ = try await run(.prepare); Issue.record("Upload failure swallowed") }
            catch { #expect(!(error is CancellationError)) }
            do { _ = try await run(.resumeAfterUser); Issue.record("Uncertain upload replayed") }
            catch { #expect((error as? ChannelFailure)?.recovery == .inspectionRequired) }
        }
        let log = try String(contentsOf: directory.appendingPathComponent("log"))
        #expect(log.components(separatedBy: "jike:upload-image").count - 1 == (["valid","reordered"].contains(mode) ? 2 : 1))
        #expect(!log.contains("page.reload"))
        #expect(try Data(contentsOf: original) == sourceBytes)
        let uploads = try String(contentsOf: directory.appendingPathComponent("uploads")).split(separator: "\n")
        #expect(uploads.allSatisfy { String($0) == prepared.assets[0].pngPath })
    }
}
