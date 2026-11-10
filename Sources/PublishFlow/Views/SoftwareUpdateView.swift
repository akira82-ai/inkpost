import SwiftUI
import PublishKit

struct SoftwareUpdateView: View {
    let controller: UpdateController
    @Bindable var model: UpdateModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("软件更新").font(InkStyle.font(12, weight: .semibold))
                Spacer()
                Button("关闭", systemImage: "xmark", action: controller.dismiss)
                    .labelStyle(.iconOnly).buttonStyle(.plain).accessibilityLabel("收起更新面板")
                    .keyboardShortcut(.cancelAction)
            }
            Text("墨").font(.custom("Songti SC", size: 28)).foregroundStyle(InkStyle.paper)
                .frame(width: 48, height: 48).background(InkStyle.ink, in: RoundedRectangle(cornerRadius: 12))
            Text(title).font(.custom("Songti SC", size: 23))
            Text(model.version.isEmpty ? "当前版本 \(controller.currentVersion)" : "\(controller.currentVersion) → \(model.version)")
                .font(InkStyle.font(11)).foregroundStyle(InkStyle.muted)
            content
            if let message = model.message {
                Text(message).font(InkStyle.font(11)).foregroundStyle(InkStyle.muted)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            if let reason = controller.blockingReason, [.available, .ready, .installing].contains(model.phase) {
                Text(reason).font(InkStyle.font(11)).foregroundStyle(InkStyle.warning)
            }
            actions
        }.padding(24).frame(width: 380).background(InkStyle.paper).foregroundStyle(InkStyle.ink)
            .preferredColorScheme(.light)
    }
    private var title: String {
        switch model.phase {
        case .idle: return "软件更新"
        case .checking: return "正在检查更新"
        case .available: return "有新版本可以使用"
        case .downloading: return "正在下载新版本"
        case .extracting: return "正在验证与准备更新"
        case .ready: return "新版已准备就绪"
        case .installing: return "正在安装并重启"
        case .latest: return "没有可安装的新版本"
        case .failed: return "暂时无法更新"
        }
    }
    @ViewBuilder private var content: some View {
        switch model.phase {
        case .available:
            ScrollView {
                Text(model.releaseNotes.isEmpty ? "此版本未提供更新说明。" : model.releaseNotes)
                    .font(InkStyle.font(12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 120)
            if model.informationOnly { Text("此条仅为版本公告，不能直接安装。").font(InkStyle.font(11)) }
        case .downloading:
            if let progress = model.progress { ProgressView(value: progress) }
            else { ProgressView().controlSize(.small) }
            Text("已下载 \(ByteCountFormatter.string(fromByteCount: Int64(clamping: model.receivedBytes), countStyle: .file))")
                .font(InkStyle.font(10)).foregroundStyle(InkStyle.muted)
        case .extracting: ProgressView(value: model.extractionProgress)
        case .checking, .installing: ProgressView().controlSize(.small)
        case .ready: Text("点击后将退出墨驿、安装更新并启动新版。渠道配置会保留。")
                .font(InkStyle.font(12)).foregroundStyle(InkStyle.muted)
        default: EmptyView()
        }
    }
    @ViewBuilder private var actions: some View {
        if model.phase == .available {
            primary("下载并更新", action: controller.beginDownload)
                .disabled(controller.blockingReason != nil || model.informationOnly)
        } else if model.phase == .ready || model.phase == .installing {
            primary("重启并使用新版", action: controller.restart).disabled(controller.blockingReason != nil)
        } else if [.idle, .failed, .latest].contains(model.phase) {
            primary("检查更新", action: controller.check).disabled(!model.isConfigured || !model.canCheck)
        }
        if model.canCancel {
            Button("取消更新", action: controller.cancel).buttonStyle(.plain).font(InkStyle.font(11))
                .frame(maxWidth: .infinity)
        }
        Button(model.installSessionActive ? "收起，稍后查看" : "稍后", action: controller.dismiss)
            .buttonStyle(.plain).font(InkStyle.font(11)).foregroundStyle(InkStyle.muted).frame(maxWidth: .infinity)
        if model.phase == .ready {
            Text("准备完成后，退出应用也可能安装更新；未处理内容会阻止退出。")
                .font(InkStyle.font(10)).foregroundStyle(InkStyle.muted)
        }
    }
    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(.plain).font(InkStyle.font(12, weight: .semibold))
            .frame(maxWidth: .infinity).frame(height: 42).foregroundStyle(InkStyle.paper)
            .background(InkStyle.ink, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct SoftwareUpdateSettings: View {
    let controller: UpdateController
    @Bindable var model: UpdateModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("软件更新").font(InkStyle.font(13, weight: .semibold))
                    Text("当前版本 \(controller.currentVersion)").font(InkStyle.font(11)).foregroundStyle(InkStyle.muted)
                }
                Spacer()
                Button(model.hasReminder ? "查看更新" : "检查更新", action: controller.show)
                    .disabled(!model.isConfigured || !model.canCheck && !model.hasReminder)
            }
            Toggle("自动检查更新", isOn: $model.automaticallyChecks)
                .onChange(of: model.automaticallyChecks) { _, value in controller.setAutomaticChecks(value) }
                .disabled(!model.isConfigured).font(InkStyle.font(12))
            Text(model.isConfigured ? "仅检查并提醒，点击后才下载；每天自动检查一次。" : model.message ?? "在线更新尚未配置。")
                .font(InkStyle.font(11)).foregroundStyle(InkStyle.muted)
        }
    }
}

struct UpdatePresentation: ViewModifier {
    let controller: UpdateController
    func body(content: Content) -> some View {
        @Bindable var model = controller.state
        content.sheet(isPresented: $model.isPresented) {
            SoftwareUpdateView(controller: controller, model: model)
        }
    }
}

