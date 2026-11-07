import Foundation
import AppKit
import Testing
@testable import PublishKit

@MainActor
struct XChannelAdapterTests {
    @Test func compositionAndLimitsPreserveInput() throws {
        let adapter = XChannelAdapter()

        #expect(adapter.expectedBody(for: .init(title: " 标题 ", body: " 正文\n\n  尾 ", tags: ["swift"])) == " 标题 \n 正文\n\n  尾 \n\n#swift")
        #expect(adapter.expectedBody(for: .init(title: "", body: "正文")) == "正文")
        try adapter.validate(.init(title: "", body: String(repeating: "中", count: 1899), assets: ["1","2","3","4"]))
        #expect(throws: ChannelFailure.self) { try adapter.validate(.init(title: "题", body: String(repeating: "中", count: 1898))) }
        #expect(throws: ChannelFailure.self) { try adapter.validate(.init(title: "", body: "正文", assets: ["1","2","3","4","5"])) }
        #expect(throws: ChannelFailure.self) { try adapter.validate(.init(title: "题", body: " \n")) }
        try adapter.validate(.init(title: "", body: String(repeating: "🖋️", count: 1899)))
    }

    @Test(arguments: ["valid", "login", "conflict", "rejected", "cancel"])
    func realAdapterUsesNativePasteAndChecksResult(_ mode: String) async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let binary = dir.appendingPathComponent("x-stub")
        let log = dir.appendingPathComponent("log")
        let request = ChannelRequest(title: "标题", body: " 正文\n\n尾 ", tags: ["x"])
        let expected = XChannelAdapter().expectedBody(for: request)
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
        if 'x:open-editor' in script:
            state['opens']+=1
            result['loginRequired']=mode=='login' and state['opens']==1
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
        if ["conflict", "rejected"].contains(mode) {
            do { _ = try await execute(.prepare); Issue.record("Invalid content accepted") } catch { #expect(error is ChannelFailure) }
            #expect(!(try String(contentsOf: log)).contains("x:paste-body"))
        } else {
            var outcome = try await execute(.prepare)
            if mode == "login" { #expect(outcome.failure?.code == .loginRequired); outcome = try await execute(.resumeAfterUser) }
            #expect(outcome.failure == nil)
            _ = try await execute(.resumeAfterUser)
            let scripts = try String(contentsOf: log)
            #expect(scripts.components(separatedBy: "x:paste-body").count - 1 == 1)
            #expect(!scripts.contains("await page.click"))
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["INKPOST_X_LIVE"] == "1"))
    func liveXComposeWithoutPublishing() async throws {
        let adapter = XChannelAdapter()
        var paths: [String] = []
        for index in 0..<2 {
            let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 80, pixelsHigh: 80, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            for y in 0..<80 { for x in 0..<80 { bitmap.setColor(index == 0 ? NSColor(deviceRed: 0.2, green: 0.4, blue: 0.9, alpha: 1) : NSColor(deviceRed: 0.9, green: 0.5, blue: 0.2, alpha: 1), atX: x, y: y) } }
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("x-live-\(UUID().uuidString).png")
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: path); paths.append(path.path)
        }
        let bridge = try EgoBridge(spaceName: try #require(ProcessInfo.processInfo.environment["INKPOST_X_LIVE_SPACE"]), engine: EgoLiteEngine(), pageLabel: try #require(ProcessInfo.processInfo.environment["INKPOST_X_LIVE_PAGE"]))
        let request = ChannelRequest(title: "墨驿 X 适配器验证", body: "  保留空格\n\n仅填写，不发布。", tags: ["测试"], assets: paths)
        let prepared = try AssetService.preparePNGAssets(request.assets)
        for command in [ChannelCommand.prepare, .resumeAfterUser] {
            let context = ChannelExecutionContext(execution: .init(taskID: UUID(), platform: .x), command: command, bridge: bridge, preparedAssets: prepared.assets,
                onEvent: { _ in })
            let outcome = try await adapter.execute(request: request, context: context)
            #expect(outcome.failure == nil)
        }
    }
}
