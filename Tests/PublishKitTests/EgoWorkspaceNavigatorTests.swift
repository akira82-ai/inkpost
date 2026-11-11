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
