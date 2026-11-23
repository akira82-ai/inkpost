import SwiftUI
import KeyboardShortcuts

struct ShortcutSettings: View {
    @Bindable var controller: ShortcutController
    @State private var enabled: Bool
    @State private var previous: KeyboardShortcuts.Shortcut

    init(controller: ShortcutController) {
        self.controller = controller
        _enabled = State(initialValue: controller.shortcut != nil)
        _previous = State(initialValue: controller.shortcut ?? ShortcutController.defaultShortcut)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            KeyboardShortcuts.Recorder("显示 / 隐藏发布窗口", shortcut: $controller.shortcut, onChange: controller.save)
            Divider()
            Toggle("启用全局快捷键", isOn: $enabled).toggleStyle(.switch)
            if let message = controller.message {
                HStack(alignment: .top) {
                    Text(message).foregroundStyle(.red)
                    Button("重试", action: controller.retry)
                }
            }
        }.font(InkStyle.font(12))
            .onChange(of: enabled) { _, value in
                if value { if controller.shortcut == nil { controller.save(previous) } }
                else {
                    if let shortcut = controller.shortcut { previous = shortcut }
                    controller.save(nil)
                }
            }
            .onChange(of: controller.shortcut) { _, value in
                if let value { previous = value }
                enabled = value != nil
            }
    }
}
