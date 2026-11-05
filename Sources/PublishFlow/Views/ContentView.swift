import SwiftUI
import PublishKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: DispatchModel
    let controller: DispatchController

    var body: some View {
        NavigationSplitView {
            List {
                Section("配置 · DeepSeek") { configSection }
                Section("目标平台") { platformSection }
                Section("图片素材") { assetsSection }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        } detail: {
            detailPane
        }
        .navigationTitle("墨驿 Inkpost")
    }

    @ViewBuilder
    private var configSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SecureField("DeepSeek API Key", text: $model.apiKey)
                .textFieldStyle(.roundedBorder)
            TextField("模型", text: $model.model)
                .textFieldStyle(.roundedBorder)
            Label("https://api.deepseek.com（默认）", systemImage: "link")
                .font(.caption).foregroundStyle(.secondary)
            if model.apiKey.isEmpty {
                Label("填入 API Key 后即可分发", systemImage: "key.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var platformSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(PlatformID.allCases.filter { $0.isAvailable }) { p in
                Toggle(isOn: Binding(
                    get: { model.selectedPlatforms.contains(p) },
                    set: { on in
                        if on { model.selectedPlatforms.append(p) }
                        else { model.selectedPlatforms.removeAll { $0 == p } }
                        if !on { model.platformPhase[p] = nil }
                    })) {
                    HStack {
                        Text(p.title)
                        Text(p.isArticle ? "文章" : "动态")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var assetsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("添加图片…") { addAssets() }
            ForEach(model.assetPaths, id: \.self) { p in
                HStack {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                    Text((p as NSString).lastPathComponent).font(.caption).lineLimit(1)
                    Spacer()
                    Button {
                        model.assetPaths.removeAll { $0 == p }
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            if model.assetPaths.isEmpty {
                Text("未添加图片").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("内容") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("标题", text: $model.title)
                        .textFieldStyle(.roundedBorder)
                    TextEditor(text: $model.markdown)
                        .font(.system(size: 13))
                        .frame(minHeight: 120)
                        .border(Color.gray.opacity(0.3))
                    TextField("话题标签（空格分隔，可带 #）", text: $model.tagsText)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(6)
            }

            // 平台状态条
            HStack(spacing: 12) {
                ForEach(model.selectedPlatforms, id: \.self) { p in
                    let ph = model.platformPhase[p] ?? .pending
                    HStack(spacing: 4) {
                        Circle()
                            .fill(color(for: ph))
                            .frame(width: 8, height: 8)
                        Text("\(p.title) · \(phaseTitle(ph))").font(.caption)
                    }
                }
                if model.selectedPlatforms.isEmpty {
                    Text("左侧勾选目标平台").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 2)

            HStack {
                Button {
                    controller.dispatch()
                } label: {
                    Label(model.overallPhase == .preparing ? "分发中…" : "开始分发", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!controller.canDispatch)

                ForEach(model.selectedPlatforms.filter { $0 == .simFixture && (model.platformPhase[$0] == .awaitingConfirm) }, id: \.self) { p in
                    Button("读取 fixture 回执") { controller.readFixtureReceipt(for: p) }
                        .buttonStyle(.bordered)
                }

                if model.overallPhase == .failed {
                    Button("重置") { controller.reset() }
                        .buttonStyle(.bordered)
                }
                Spacer()
            }

            if let err = model.errorMessage {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.callout)
            }
            if model.overallPhase == .awaitingConfirm {
                Label("草稿就绪：请到 ego 浏览器检查每份草稿并亲手发布（即刻弹窗不要关闭）", systemImage: "hand.raised.fill")
                    .foregroundStyle(.green).font(.callout)
            }
            HStack {
                TextField("发布后手动粘贴链接（真实平台回执）", text: $model.manualReceipt)
                    .textFieldStyle(.roundedBorder)
                if let u = URL(string: model.manualReceipt), u.scheme != nil {
                    Link("打开", destination: u)
                }
            }

            GroupBox("Agent 运行日志") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(model.eventLog.enumerated().reversed()), id: \.offset) { _, line in
                            Text(line).font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if model.eventLog.isEmpty {
                            Text("点击「开始分发」后，agent 在每个平台的步骤会显示在这里")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(6)
                }
                .frame(minHeight: 170)
            }
        }
        .padding(16)
    }

    private func color(for ph: TargetPhase) -> Color {
        switch ph {
        case .pending: return .secondary
        case .preparing, .finalizing: return .blue
        case .awaitingConfirm, .published: return .green
        case .needLogin: return .orange
        case .failed: return .red
        }
    }
    private func addAssets() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK {
            controller.addAssets(panel.urls.map { $0.path })
        }
    }

    private func phaseTitle(_ phase: TargetPhase) -> String {
        switch phase {
        case .pending: return "未开始"
        case .preparing: return "分发中"
        case .awaitingConfirm: return "草稿就绪"
        case .needLogin: return "需登录"
        case .finalizing: return "读取回执中"
        case .published: return "已发布"
        case .failed: return "失败"
        }
    }
}
