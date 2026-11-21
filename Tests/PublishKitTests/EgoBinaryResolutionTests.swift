import Testing
@testable import PublishKit

struct EgoBinaryResolutionTests {
    @Test func systemLaunchFindsOfficialUserInstallation() throws {
        let path = try EgoLiteEngine.resolveBinaryPath(searchPath: "/usr/bin:/bin:/usr/sbin:/sbin", homeDirectory: "/Users/test") {
            $0 == "/Users/test/.local/bin/ego-browser"
        }
        #expect(path == "/Users/test/.local/bin/ego-browser")
    }

    @Test func explicitAbsoluteSearchPathRetainsPriority() throws {
        let path = try EgoLiteEngine.resolveBinaryPath(searchPath: "/custom/bin", homeDirectory: "/Users/test") {
            ["/custom/bin/ego-browser", "/Users/test/.local/bin/ego-browser"].contains($0)
        }
        #expect(path == "/custom/bin/ego-browser")
    }

    @Test func relativeAndEmptyEntriesAreNotExecuted() throws {
        var checked: [String] = []
        #expect(throws: EgoLiteEngine.EngineError.self) {
            _ = try EgoLiteEngine.resolveBinaryPath(searchPath: ":.:relative", homeDirectory: "/Users/test") {
                checked.append($0); return false
            }
        }
        #expect(checked.allSatisfy { $0.hasPrefix("/") })
    }

    @Test func absentCLIReportsInstallationError() {
        #expect(throws: EgoLiteEngine.EngineError.self) {
            _ = try EgoLiteEngine.resolveBinaryPath(searchPath: "", homeDirectory: "/Users/test", isExecutable: { _ in false })
        }
    }
}
