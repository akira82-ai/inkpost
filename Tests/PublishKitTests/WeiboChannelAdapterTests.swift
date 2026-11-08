import Foundation
import AppKit
import Testing
@testable import PublishKit

@MainActor
struct WeiboChannelAdapterTests {
    @Test func completeInputAndWhitespaceArePreserved() throws {
        let adapter = WeiboChannelAdapter()
        let request = ChannelRequest(title: " 标题 ", body: "  正文🧪\n\n  #AI\t尾  ", html: " <p>unused</p> ", assets: ["a", "b"])
        let original = request
        #expect(adapter.expectedBody(for: request) == " 标题 \n" + request.body)
        #expect(adapter.expectedBody(for: .init(title: "", body: request.body)) == request.body)
        #expect(adapter.expectedBody(for: .init(title: " ", body: "正文")) == " \n正文")
        #expect(adapter.capabilities.usesTitle)
        try adapter.validate(request)
        #expect(request == original)
        #expect(ChannelRegistry.standard.adapter(for: .weibo) != nil)
        #expect(throws: ChannelFailure.self) { try adapter.validate(.init(title: "题", body: " \n")) }
        // No invented account limit: actual editor acceptance decides long input support.
        try adapter.validate(.init(title: "", body: String(repeating: "中", count: 2001)))
    }

    @Test(arguments: ["valid", "login", "conflict", "rejected", "cancel", "unknownBody", "closedPanel"])
    func realAdapterUsesNativePasteAndChecksResult(_ mode: String) async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let binary = dir.appendingPathComponent("weibo-stub")
        let log = dir.appendingPathComponent("log")
        let request = ChannelRequest(title: "标题", body: " 正文\n\n尾 ")
        let expected = WeiboChannelAdapter().expectedBody(for: request)
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
        if 'weibo:open-editor' in script:
            state['opens']+=1
            result['loginRequired']=mode=='login' and state['opens']==1
        if 'weibo:check-quick-publish' in script:result['present']=not(mode=='closedPanel' and state['opens']>1)
        if 'weibo:paste-body' in script:
            if mode=='unknownBody':result={'ok':False,'error':'paste result unknown'}
            else:state['body']=\(String(reflecting: expected))
        if 'weibo:read-page' in script:result['value']={'body':'other' if mode=='conflict' else state['body'],'images':[],'busy':False,'rejected':mode=='rejected','accepted':True}
        path.write_text(json.dumps(state))
        print(json.dumps(result))
        """
        try source.write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
        let bridge = try EgoBridge(spaceName: "weibo-stub", engine: EgoLiteEngine(binaryPath: binary.path))
        let adapter = WeiboChannelAdapter()
        func execute(_ command: ChannelCommand) async throws -> ChannelOutcome {
            let context = ChannelExecutionContext(execution: .init(taskID: UUID(), platform: .weibo), command: command,
                bridge: bridge, onEvent: { _ in })
            return try await adapter.execute(request: request, context: context)
        }
        if mode == "cancel" {
            let task = Task { try await execute(.prepare) }; task.cancel()
            do { _ = try await task.value; Issue.record("Cancellation swallowed") } catch { #expect(error is CancellationError) }
            return
        }
        if mode == "unknownBody" {
            for command in [ChannelCommand.prepare, .resumeAfterUser] {
                do { _ = try await execute(command); Issue.record("Uncertain body write accepted") }
                catch { #expect((error as? ChannelFailure)?.recovery == .inspectionRequired) }
            }
            #expect(try String(contentsOf: log).components(separatedBy: "weibo:paste-body").count - 1 == 1)
        } else if ["conflict", "rejected"].contains(mode) {
            do { _ = try await execute(.prepare); Issue.record("Invalid content accepted") }
            catch {
                let failure = try #require(error as? ChannelFailure)
                #expect(failure.stage == .fillingContent)
                if mode == "conflict" {
                    #expect(failure.recovery == .inspectionRequired)
                    #expect(failure.detail.contains("已有不同的草稿"))
                }
            }
            #expect(!(try String(contentsOf: log)).contains("weibo:paste-body"))
            #expect(!(try String(contentsOf: log)).contains("weibo:paste-image"))
        } else {
            var outcome = try await execute(.prepare)
            if mode == "login" { #expect(outcome.failure?.code == .loginRequired); outcome = try await execute(.resumeAfterUser) }
            #expect(outcome.failure == nil)
            if mode == "closedPanel" {
                do { _ = try await execute(.resumeAfterUser); Issue.record("Closed composer accepted") }
                catch {
                    #expect((error as? ChannelFailure)?.code == .editorUnavailable)
                    #expect((error as? ChannelFailure)?.recovery == .inspectionRequired)
                }
            } else { _ = try await execute(.resumeAfterUser) }
            let scripts = try String(contentsOf: log)
            #expect(scripts.components(separatedBy: "weibo:paste-body").count - 1 == 1)
            #expect(scripts.components(separatedBy: "weibo:open-quick-publish").count - 1 == 1)
            #expect(scripts.contains(".woo-modal-main .wbpro-layer textarea"))
            #expect(scripts.contains("document.activeElement === editors[0]"))
            #expect(!scripts.contains("page.reload"))
            #expect(!scripts.contains("page.click(\"text=发送"))
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["INKPOST_WEIBO_LIVE"] == "1"))
    func liveWeiboComposeWithoutPublishing() async throws {
        let adapter = WeiboChannelAdapter()
        var paths: [String] = []
        for index in 0..<2 {
            let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 80, pixelsHigh: 80, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            for y in 0..<80 { for x in 0..<80 { bitmap.setColor(index == 0 ? NSColor(deviceRed: 0.2, green: 0.4, blue: 0.9, alpha: 1) : NSColor(deviceRed: 0.9, green: 0.5, blue: 0.2, alpha: 1), atX: x, y: y) } }
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("weibo-live-\(UUID().uuidString).png")
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: path); paths.append(path.path)
        }
        let bridge = try EgoBridge(spaceName: try #require(ProcessInfo.processInfo.environment["INKPOST_WEIBO_LIVE_SPACE"]), engine: EgoLiteEngine(), pageLabel: try #require(ProcessInfo.processInfo.environment["INKPOST_WEIBO_LIVE_PAGE"]))
        let request = ChannelRequest(title: "墨驿微博适配器验证", body: "  保留空格🧪\n\n仅填写，不发布。  ", assets: paths)
        let prepared = try AssetService.preparePNGAssets(request.assets)
        for command in [ChannelCommand.prepare, .resumeAfterUser] {
            let context = ChannelExecutionContext(execution: .init(taskID: UUID(), platform: .weibo), command: command, bridge: bridge, preparedAssets: prepared.assets,
                onEvent: { _ in })
            let outcome = try await adapter.execute(request: request, context: context)
            #expect(outcome.failure == nil)
        }
    }
}

@MainActor
struct WeiboImageTests {
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
        if 'weibo:open-editor' in script:result['loginRequired']=False
        if 'weibo:check-quick-publish' in script:result['present']=True
        if 'weibo:paste-body' in script:state['body']='unused\\nBody'
        if 'weibo:paste-image' in script:
            state['uploads']+=1
            if mode=='unknown':result={'ok':False,'error':'write result unknown'}
            else:state['images'].append({'identity':str(state['uploads']), 'ready':True})
        if 'weibo:wait-images' in script:
            if mode=='timeout':result={'ok':False,'error':'upload timeout'}
        if 'weibo:read-page' in script:result['value']={'body':state['body'],'images':list(reversed(state['images'])) if state['reverse'] else state['images'],'accepted':True,'rejected':False,'busy':False}
        path.write_text(json.dumps(state))
        print(json.dumps(result))
        """
        try source.write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
        let bridge = try EgoBridge(spaceName: "image-stub", engine: EgoLiteEngine(binaryPath: binary.path))
        let adapter = WeiboChannelAdapter()
        let request = ChannelRequest(title: "unused", body: "Body", html: "unused", assets: [original.path, original.path])
        let prepared = try AssetService.preparePNGAssets(request.assets)
        func run(_ command: ChannelCommand) async throws -> ChannelOutcome {
            try await adapter.execute(request: request, context: .init(execution: .init(taskID: UUID(), platform: .weibo), command: command, bridge: bridge, preparedAssets: prepared.assets, onEvent: { _ in }))
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
                do { _ = try await run(.resumeAfterUser); Issue.record("Changed images accepted") }
                catch { #expect((error as? ChannelFailure)?.recovery == .inspectionRequired) }
            } else { #expect(try await run(.resumeAfterUser).failure == nil) }
        } else {
            do { _ = try await run(.prepare); Issue.record("Upload failure swallowed") }
            catch { #expect(!(error is CancellationError)) }
            do { _ = try await run(.resumeAfterUser); Issue.record("Uncertain upload replayed") }
            catch { #expect((error as? ChannelFailure)?.recovery == .inspectionRequired) }
        }
        let log = try String(contentsOf: directory.appendingPathComponent("log"))
        #expect(log.components(separatedBy: "weibo:paste-image").count - 1 == (["valid","reordered","deleted","replaced"].contains(mode) ? 2 : 1))
        #expect(!log.contains("page.reload"))
        #expect(try Data(contentsOf: original) == sourceBytes)
        #expect(prepared.assets.allSatisfy { $0.pngPath.hasSuffix(".png") && $0.pngPath != original.path })
    }
}
