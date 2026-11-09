import SwiftUI
import PublishKit

@main
struct PublishFlowApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycle.self) private var lifecycle
    @State private var controller = DispatchController(service: DispatchService(), settings: DispatchSettings(), onCompletion: CompletionNoticePresentation.deliver)
    @State private var presentation = TaskPresentation()
    var body: some Scene {
        Window("墨驿 Inkpost", id: "workspace") {
            DispatchRootView(controller: controller)
                .background(MenuBarInstallation(lifecycle: lifecycle, controller: controller, presentation: presentation))
                .modifier(TaskWindowPresentation(model: controller.state, presentation: presentation, compact: false))
        }.defaultSize(width: 1180, height: 780)
    }
}
