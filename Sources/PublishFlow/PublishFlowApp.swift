import SwiftUI
import PublishKit

@main
struct PublishFlowApp: App {
    @State private var controller = DispatchController(service: AgentDispatchService(), settings: DispatchSettings())
    var body: some Scene {
        WindowGroup {
            DispatchRootView(controller: controller)
        }
    }
}
