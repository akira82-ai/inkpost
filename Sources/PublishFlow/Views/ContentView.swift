import SwiftUI
import PublishKit

struct ContentView: View {
    @Bindable var model: DispatchModel
    let controller: DispatchController
    @State private var page = WorkspacePage.compose
    @State private var settings = false
    private enum WorkspacePage: String { case compose = "新的投递", tasks = "投递记录", channels = "渠道管理" }
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                HStack {
                    Text("工作台").foregroundStyle(InkStyle.muted)
                    Text("/").foregroundStyle(InkStyle.placeholder)
                    Text(page.rawValue)
                    Spacer()
                    Text("内容与简约界面同步").font(InkStyle.font(10)).foregroundStyle(InkStyle.muted)
                }.font(InkStyle.font(12)).padding(.horizontal, 29).frame(height: 64)
                Rectangle().fill(InkStyle.line).frame(height: 1)
                switch page {
                case .compose: compose
                case .tasks: taskRecord
                case .channels: channels
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.background(InkStyle.paper).foregroundStyle(InkStyle.ink).preferredColorScheme(.light)
            .modifier(NoticeOverlay(model: model))
            .sheet(isPresented: $settings) { ConfigurationView(model: model, controller: controller) }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            InkBrand(compact: false).padding(.horizontal, 6).padding(.top, 22).padding(.bottom, 23)
            navigation(.compose, symbol: "arrow.up.right")
            navigation(.tasks, symbol: "clock")
            navigation(.channels, symbol: "square.grid.2x2")
            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                Text("一个工作区").foregroundStyle(InkStyle.ink)
                Text("各渠道独立抵达").foregroundStyle(InkStyle.muted)
            }.font(InkStyle.font(11)).padding(.horizontal, 9).padding(.bottom, 12)
            Rectangle().fill(InkStyle.line).frame(height: 1)
            Button { settings = true } label: {
                Label("偏好设置", systemImage: "gearshape").font(InkStyle.font(11)).foregroundStyle(InkStyle.muted)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }.buttonStyle(.plain)
        }.padding(14).frame(width: 190).background(Color(hex: 0xF0F0E9))
            .overlay(alignment: .trailing) { Rectangle().fill(InkStyle.line).frame(width: 1) }
    }
    private func navigation(_ destination: WorkspacePage, symbol: String) -> some View {
        Button { page = destination } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 16)
                Text(destination.rawValue)
                Spacer()
            }.font(InkStyle.font(12, weight: page == destination ? .semibold : .regular))
                .foregroundStyle(page == destination ? Color(hex: 0x303A28) : Color(hex: 0x74796C))
                .padding(.horizontal, 13).padding(.vertical, 12)
                .background(page == destination ? Color(hex: 0xE1E3D8) : .clear, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain)
    }
    private var compose: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("YOUR WORDS, EVERYWHERE.").font(InkStyle.font(10)).tracking(3).foregroundStyle(InkStyle.muted)
                Text("下一次表达，从这里出发。").font(.custom("Songti SC", size: 29)).padding(.top, 8).padding(.bottom, 27)
                HStack(alignment: .top, spacing: 29) {
                    VStack(spacing: 0) {
                        HStack(spacing: 18) {
                            Text("Markdown")
                            Text("·")
                            Text("B").bold()
                            Text("I").italic()
                            Spacer()
                            Text("纯文本编辑").font(InkStyle.font(10))
                        }.font(InkStyle.font(12)).foregroundStyle(Color(hex: 0x929589))
                            .padding(.horizontal, 17).padding(.vertical, 12).background(Color(hex: 0xF7F7F1))
                        Rectangle().fill(InkStyle.line).frame(height: 1)
                        VStack(spacing: 0) {
                            ComposerFields(model: model, expanded: true, onImages: controller.pasteImage, onFiles: controller.addAssets)
                            AttachmentStrip(model: model, controller: controller)
                        }.padding(.horizontal, 23).padding(.top, 12).padding(.bottom, 12)
                        Rectangle().fill(InkStyle.line).frame(height: 1)
                        HStack(spacing: 9) {
                            Text("＃").foregroundStyle(InkStyle.muted)
                            TextField("多个话题以空格分隔", text: $model.tagsText).textFieldStyle(.plain).font(InkStyle.font(11))
                                .disabled(model.overallPhase != .pending)
                        }.padding(.horizontal, 18).padding(.vertical, 13)
                    }.background(Color(hex: 0xFFFEFB)).clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(InkStyle.line))
                        .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack { Text("选择投递渠道"); Spacer(); Text("\(model.selectedPlatforms.count) 个渠道").foregroundStyle(InkStyle.muted) }
                            .font(InkStyle.font(12)).padding(.bottom, 15)
                        ScrollView { channelCards }.frame(height: 480)
                    }.frame(width: 270)
                }
                Rectangle().fill(InkStyle.line).frame(height: 1).padding(.top, 24).padding(.bottom, 20)
                HStack(alignment: .center, spacing: 24) {
                    VStack(alignment: .leading, spacing: 5) {
                        if model.overallPhase == .pending {
                            Text("准备好，即可出发").foregroundStyle(InkStyle.ink)
                            Text("各渠道独立执行，遇到登录可稍后继续").foregroundStyle(InkStyle.muted)
                        } else { DispatchStatus(model: model, controller: controller) }
                    }.font(InkStyle.font(11)).frame(maxWidth: .infinity, alignment: .leading)
                    DispatchAction(model: model, controller: controller).frame(width: 245)
                }
                Text("填写完成后，请到浏览器检查内容并亲手点击发布。")
                    .font(InkStyle.font(10)).foregroundStyle(InkStyle.placeholder).padding(.top, 18)
                if model.overallPhase == .awaitingConfirm {
                    Button("开始新一份", action: controller.newDraft).buttonStyle(.plain).font(InkStyle.font(11)).padding(.top, 12)
                } else if model.overallPhase == .failed {
                    Button("修改未完成渠道的内容", action: controller.editUnfinishedChannels).buttonStyle(.plain).font(InkStyle.font(11)).padding(.top, 12)
                }
            }.padding(.horizontal, 32).padding(.top, 33).padding(.bottom, 24)
        }
    }
    private var channelCards: some View {
        VStack(spacing: 9) {
            ForEach(ChannelPresentation.all) { channel in
                VStack(alignment: .leading, spacing: 11) {
                    HStack(spacing: 10) {
                        ChannelBadge(channel: channel, size: 29)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(channel.name).font(InkStyle.font(12, weight: .semibold))
                            Text(channel.available ? (channel.platform?.isArticle == true ? "专栏文章" : "图文动态") : "待适配 · 暂不可选")
                                .font(InkStyle.font(10)).foregroundStyle(InkStyle.muted)
                        }
                        Spacer(minLength: 0)
                        Toggle(channel.name, isOn: Binding(get: { channel.isSelected(in: model) }, set: { _ in if let p = channel.platform { controller.select(p) } }))
                            .labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(Color(hex: 0x626F54))
                            .disabled(!channel.available || model.overallPhase != .pending)
                    }
                    Text(channelState(channel)).font(InkStyle.font(10)).foregroundStyle(channel.available ? InkStyle.muted : InkStyle.warning)
                        .padding(.leading, 39)
                }.padding(13).frame(maxWidth: .infinity, alignment: .leading).background(Color(hex: 0xFFFEFB), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(InkStyle.line))
            }
        }.padding(1)
    }
    private func channelState(_ channel: ChannelPresentation) -> String {
        guard let platform = channel.platform, channel.available else { return "实际填写与登录恢复能力尚待验证" }
        switch model.platformPhase[platform] ?? .pending {
        case .preparing: return "正在填写内容…"
        case .awaitingConfirm: return "已填好 · 请在浏览器检查"
        case .needLogin: return "需要登录 · 处理后继续"
        case .failed: return "需要您手工处理"
        default: return "等待填写 · 执行时检查登录状态"
        }
    }
    private var taskRecord: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("本次投递").font(.custom("Songti SC", size: 26))
            Text("这里只显示本次运行记录，尚不保存历史投递。")
                .font(InkStyle.font(12)).foregroundStyle(InkStyle.muted)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if model.eventLog.isEmpty { Text("开始填写后，各渠道的执行过程会出现在这里。").foregroundStyle(InkStyle.muted) }
                    ForEach(Array(model.eventLog.enumerated()), id: \.offset) { _, line in Text(line).textSelection(.enabled) }
                }.font(InkStyle.font(11)).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private var channels: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("渠道与账号，集中管理。").font(.custom("Songti SC", size: 26))
                Text("已接入知乎、即刻和 X。账号登录状态将在填写时检查；其余平台为待适配渠道。")
                    .font(InkStyle.font(12)).foregroundStyle(InkStyle.muted)
                channelCards
            }.padding(32)
        }
    }
}

struct ConfigurationView: View {
    @Bindable var model: DispatchModel
    let controller: DispatchController
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("偏好设置").font(.custom("Songti SC", size: 26))
            Text("模型配置 · DeepSeek").font(InkStyle.font(12, weight: .semibold))
            SecureField("API Key", text: $model.apiKey).textFieldStyle(.roundedBorder)
            TextField("模型", text: $model.model).textFieldStyle(.roundedBorder)
            Text("https://api.deepseek.com").font(InkStyle.font(11)).foregroundStyle(InkStyle.muted)
            HStack { Spacer(); Button("完成") { controller.saveConfig(); dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 420).background(InkStyle.paper).foregroundStyle(InkStyle.ink)
            .preferredColorScheme(.light)
    }
}
