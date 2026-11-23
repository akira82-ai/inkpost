import AppKit
import SwiftUI
import Testing
import PublishKit
@testable import PublishFlow

@MainActor
struct SettingsViewTests {
    @Test func settingsFitsCompactWindowWithoutMutatingDraft() throws {
        _ = NSApplication.shared
        let controller = DispatchController(service: DispatchService(), settings: DispatchSettings())
        controller.state.title = "Existing title"
        controller.state.markdown = "Keep this draft\n\nwith spacing"
        let view = NSHostingView(rootView: ContentView(model: controller.state, controller: controller,
            shortcuts: ShortcutController()))
        view.frame = NSRect(x: 0, y: 0, width: 685, height: 530)
        view.layoutSubtreeIfNeeded()
        #expect(view.fittingSize.width <= 700)
        #expect(view.fittingSize.height <= 550)
        #expect(controller.state.title == "Existing title")
        #expect(controller.state.markdown == "Keep this draft\n\nwith spacing")
    }
}
