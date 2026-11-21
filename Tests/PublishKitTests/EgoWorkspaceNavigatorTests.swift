import Foundation
import Testing
@testable import PublishKit

@MainActor
struct EgoWorkspaceNavigatorTests {
    @Test(arguments: [-1, 0, Int(Int32.max) + 1])
    func invalidWindowIdentityFailsBeforeClaimingAnySpace(windowID: Int) throws {
        #expect(throws: WorkspaceNavigationError.self) {
            _ = try EgoWorkspaceNavigator.claimCurrentSpaceScript(windowID: windowID, title: "Test")
        }
    }
}

@MainActor
struct RetryPageScriptTests {
    @Test(arguments: ["success", "closeFailure", "createFailure", "ambiguous", "missing", "userOwned", "alreadyClosed"])
    func replacesOnlyVerifiedOldPage(mode: String) throws {
        let script = try DispatchService.retryPageScript(spaceID: 42, label: mode == "alreadyClosed" ? "" : "p1", url: "https://channel.test/draft", completed: true)
        let harness = """
        const mode = "\(mode)";
        const calls = [];
        let tabs = [{url:"https://channel.test/draft",targetId:"old",openedBy:mode === "userOwned" ? "unknown" : "agent",page:{}},
                    {url:"https://other.test",targetId:"other",openedBy:"agent",page:{}}];
        if (mode === "ambiguous") tabs.push({...tabs[0],targetId:"duplicate"});
        if (mode === "missing" || mode === "alreadyClosed") tabs.shift();
        const mockTask = {
          tabs:async()=>tabs,
          adopt:async()=>({close:async()=>{calls.push("close");if(mode === "closeFailure") throw Error("close failed"); tabs=tabs.filter(t=>t.targetId!=="old");}}),
          newPage:async()=>{calls.push("new");if(mode === "createFailure") throw Error("create failed");return {label:"fresh"};},
          finish:async()=>calls.push("finish")
        };
        const listTaskSpaces = async()=>[{id:42,ownership:"user"}];
        const claimTaskSpace = async()=>{calls.push("claim");return mockTask;};
        const cliLog = text=>console.log(JSON.stringify({result:JSON.parse(text),calls,tabs}));
        \(script)
        """
        let output = try Shell.capture("/usr/bin/env", ["node", "--input-type=module", "-e", harness])
        let json = try #require(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        let calls = try #require(json["calls"] as? [String])
        let result = try #require(json["result"] as? [String: Any])
        if mode == "success" { #expect(calls == ["claim", "close", "new"]); #expect(result["ok"] as? Bool == true) }
        if mode == "alreadyClosed" { #expect(calls == ["claim", "new"]) }
        if mode == "closeFailure" { #expect(calls == ["claim", "close", "finish"]); #expect(result["closed"] as? Bool == false) }
        if mode == "createFailure" { #expect(calls == ["claim", "close", "new", "finish"]); #expect(result["closed"] as? Bool == true) }
        if ["ambiguous", "missing", "userOwned"].contains(mode) { #expect(calls == ["claim", "finish"]) }
        let tabs = try #require(json["tabs"] as? [[String: Any]])
        #expect(tabs.contains { $0["targetId"] as? String == "other" })
    }
}
