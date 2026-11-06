import SwiftUI
import PublishKit

@main
struct PublishFlowApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycle.self) private var lifecycle
    @State private var controller = DispatchController(service: AgentDispatchService(), settings: DispatchSettings())
    var body: some Scene {
        MenuBarExtra("墨驿", systemImage: "square.and.pencil") {
            CompactView(model: controller.state, controller: controller)
        }.menuBarExtraStyle(.window)
        Window("墨驿 Inkpost", id: "workspace") {
            DispatchRootView(controller: controller)
        }.defaultSize(width: 1000, height: 720)
        Settings {
            DispatchRootView(controller: controller)
        }
    }
}
