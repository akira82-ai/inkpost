import SwiftUI
import KeyboardShortcuts

struct ShortcutSettings: View {
    @Bindable var controller: ShortcutController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("全局快捷键").font(InkStyle.font(13, weight: .semibold))
            KeyboardShortcuts.Recorder("显示／隐藏墨驿", shortcut: $controller.shortcut, onChange: controller.save)
            Text("默认 ⌘＋'（单引号）。点击录入可修改，清除即停用；墨驿运行时有效。")
                .font(InkStyle.font(12)).foregroundStyle(InkStyle.muted)
            if let message = controller.message {
                HStack(alignment: .top) {
                    Text(message).font(InkStyle.font(12)).foregroundStyle(.red)
                    Button("重试", action: controller.retry)
                }
            } else {
                Text(controller.isRegistered ? "已启用，切换发布窗口的显示／隐藏，保留内容和任务状态。" :
                     controller.shortcut == nil ? "已停用，仍可点击菜单栏图标打开。" : "正在设置快捷键…")
                    .font(InkStyle.font(12)).foregroundStyle(InkStyle.muted)
            }
        }
    }
}
