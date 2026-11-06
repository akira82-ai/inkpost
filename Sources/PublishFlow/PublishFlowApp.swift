import SwiftUI
import PublishKit

@main
struct PublishFlowApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycle.self) private var lifecycle
    @State private var controller = DispatchController(service: AgentDispatchService(), settings: DispatchSettings())
    var body: some Scene {
        MenuBarExtra {
            CompactView(model: controller.state, controller: controller)
        } label: {
            Text("墨").font(.custom("Songti SC", size: 18)).accessibilityLabel("墨驿快速投递")
        }.menuBarExtraStyle(.window)
        Window("墨驿 Inkpost", id: "workspace") {
            DispatchRootView(controller: controller)
        }.defaultSize(width: 1180, height: 780)
        Settings {
            ConfigurationView(model: controller.state, controller: controller)
        }
    }
}
