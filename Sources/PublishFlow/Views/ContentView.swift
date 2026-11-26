import SwiftUI
import PublishKit

/// A single settings window; publishing remains in the composer.
struct ContentView: View {
    let model: DispatchModel
    let controller: DispatchController
    var updates: UpdateController? = nil
    var shortcuts: ShortcutController? = nil
    @State private var selection = "通用"
    @State private var dependency = EgoDependencyController()
    private let pages = [("通用", "slider.horizontal.3"), ("AI 辅助", "sparkles"), ("软件更新", "arrow.triangle.2.circlepath")]

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text("墨").font(.custom("Songti SC", size: 25)).foregroundStyle(InkStyle.paper)
                        .frame(width: 36, height: 36).background(InkStyle.ink, in: RoundedRectangle(cornerRadius: 10))
                    Text("墨驿").font(InkStyle.font(16, weight: .semibold))
                }.padding(.bottom, 24)
                ForEach(pages, id: \.0) { title, icon in
                    Button { selection = title } label: {
                        Label(title, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(selection == title ? InkStyle.selected : .clear, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).accessibilityAddTraits(selection == title ? .isSelected : [])
                }
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Circle().fill(dependency.isReady ? Color.green : Color.orange).frame(width: 5, height: 5)
                        Text("ego Lite").font(InkStyle.font(11, weight: .semibold))
                        Spacer()
                        Text(dependency.status).font(InkStyle.font(10)).foregroundStyle(InkStyle.muted)
                    }
                    if !dependency.isReady && dependency.status != "正在检测" {
                        Button(dependency.actionTitle) { dependency.performAction() }
                            .disabled(dependency.isChecking)
                        if let error = dependency.message {
                            Text(error).font(InkStyle.font(10)).foregroundStyle(InkStyle.muted).lineLimit(3).help(error)
                        }
                    }
                }.padding(10).background(InkStyle.selected.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }.padding(16).frame(width: 174).background(Color(red: 0.95, green: 0.95, blue: 0.92))
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(selection).font(.custom("Songti SC", size: 27))
                    switch selection {
                    case "通用":
                        if let shortcuts { ShortcutSettings(controller: shortcuts).settingsGroup() }
                        VStack(alignment: .leading, spacing: 14) {
                            Text("窗口行为").font(InkStyle.font(11)).foregroundStyle(InkStyle.muted)
                            Text("在当前桌面打开").font(InkStyle.font(13, weight: .semibold))
                            Text("唤起时正常置前，切换应用后遵循系统排序。")
                                .font(InkStyle.font(11)).foregroundStyle(InkStyle.muted)
                            Divider()
                            Text("菜单栏常驻").font(InkStyle.font(13, weight: .semibold))
                            Text("右键菜单栏图标，可打开设置或退出墨驿。")
                                .font(InkStyle.font(11)).foregroundStyle(InkStyle.muted)
                        }.settingsGroup()
                    case "AI 辅助":
                        AISettingsView().settingsGroup()
                    default:
                        if let updates { SoftwareUpdateSettings(controller: updates, model: updates.state) }
                        VStack(spacing: 0) {
                            resource("X · @AgiRay1015", url: "https://x.com/AgiRay1015")
                            Divider()
                            resource("GitHub · 墨驿项目主页", url: "https://github.com/akira82-ai/inkpost")
                            Divider()
                            resource("飞书", url: "https://my.feishu.cn/wiki/QWQHwA9uYibmtzkZLJBccaEhnNd")
                        }.settingsGroup()
                    }
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(26)
            }.frame(width: 510)
        }.frame(height: 530).background(InkStyle.paper).foregroundStyle(InkStyle.ink)
            .preferredColorScheme(.light)
            .task { await dependency.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                Task { await dependency.refresh() }
            }
    }

    private func resource(_ title: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack { Text(title); Spacer(); Image(systemName: "arrow.up.right") }
                .font(InkStyle.font(12)).padding(.vertical, 10).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

private extension View {
    func settingsGroup() -> some View {
        padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.gray.opacity(0.15)))
    }
}
