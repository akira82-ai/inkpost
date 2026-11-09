import SwiftUI
import PublishKit

@main
struct PublishFlowApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycle.self) private var lifecycle
    @State private var controller = DispatchController(service: DispatchService(), settings: DispatchSettings(), onCompletion: CompletionNoticePresentation.deliver)
    @State private var presentation = TaskPresentation()
    var body: some Scene {
        Window("墨驿", id: "main") {
            CompactView(model: controller.state, controller: controller, presentation: presentation)
                .background(MenuBarInstallation(lifecycle: lifecycle, controller: controller, presentation: presentation))
        }
        .defaultSize(width: 420, height: 520)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .windowArrangement) {
                Button("显示墨驿") { lifecycle.showMainWindow() }
                    .keyboardShortcut("0", modifiers: [.command])
            }
        }
        Settings {
            DispatchRootView(controller: controller)
        }
    }
}
