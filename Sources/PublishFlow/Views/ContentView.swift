import SwiftUI
import PublishKit

/// Settings contains channel capabilities and software updates; editing stays in the main window.
struct ContentView: View {
    let model: DispatchModel
    let controller: DispatchController
    var updates: UpdateController? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("设置").font(.custom("Songti SC", size: 26))
            Text("渠道能力").font(InkStyle.font(13, weight: .semibold))
            Text("账号登录状态在填写时检查。内容编辑、渠道选择与任务操作统一在主窗口完成。")
                .font(InkStyle.font(12)).foregroundStyle(InkStyle.muted)
            ForEach(ChannelPresentation.all.filter(\.available)) { channel in
                HStack(spacing: 10) {
                    ChannelBadge(channel: channel)
                    Text(channel.name)
                    Spacer()
                    Text("已接入").foregroundStyle(InkStyle.muted)
                }.font(InkStyle.font(12)).padding(.vertical, 6)
            }
            if let updates { SoftwareUpdateSettings(controller: updates, model: updates.state) }
        }.padding(28).frame(width: 460)
            .background(InkStyle.paper).foregroundStyle(InkStyle.ink).preferredColorScheme(.light)
    }
}
