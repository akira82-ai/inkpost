import SwiftUI
import PublishKit

struct PublishFlowApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycle.self) private var lifecycle
    @State private var controller = DispatchController(service: DispatchService(), settings: DispatchSettings(), onCompletion: CompletionNoticePresentation.deliver)
    @State private var presentation = TaskPresentation()
    @State private var updates = UpdateController()
    var body: some Scene {
        Window("墨驿", id: "main") {
            CompactView(model: controller.state, controller: controller, presentation: presentation)
                .background(MenuBarInstallation(lifecycle: lifecycle, controller: controller, presentation: presentation, updates: updates))
                .modifier(UpdatePresentation(controller: updates))
                .onAppear {
                    updates.activate = { lifecycle.showMainWindow() }
                    updates.start(task: controller.state)
                    lifecycle.configureUpdates(updates)
                }
        }
        .defaultSize(width: 420, height: 520)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("检查更新…", action: updates.show)
                    .disabled(!updates.state.isConfigured)
            }
            CommandGroup(after: .windowArrangement) {
                Button("显示墨驿") { lifecycle.showMainWindow() }
                    .keyboardShortcut("0", modifiers: [.command])
            }
        }
        Settings {
            DispatchRootView(controller: controller, updates: updates, shortcuts: lifecycle.shortcuts)
        }
    }
}
