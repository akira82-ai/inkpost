import SwiftUI
import PublishKit
import UniformTypeIdentifiers

@main
struct PublishFlowApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 660)
        }
    }
}

// MARK: - 状态

enum PlatformPhase: String {
    case idle = "未开始"
    case running = "分发中"
    case draftReady = "草稿就绪"
    case needLogin = "需登录"
    case failed = "失败"
}

@MainActor
@Observable
final class AppModel {
    // 内容
    var title = ""
    var markdown = ""
    var tagsText = ""
    var assetPaths: [String] = []

    // 平台选择
    var selectedPlatforms: [PlatformID] = [.zhihu, .jike, .x]
    var platformPhase: [PlatformID: PlatformPhase] = [:]

    // 配置（DeepSeek）
    var apiKey = UserDefaults.standard.string(forKey: "deepseek.apiKey") ?? ""
    var model = UserDefaults.standard.string(forKey: "deepseek.model") ?? "deepseek-chat"
    static let defaultBaseURL = "https://api.deepseek.com"

    // 运行状态
    var overallPhase: DispatchPhase = .idle
    var eventLog: [String] = []
    var manualReceipt = ""
    var errorMessage: String?

    @ObservationIgnored private var runningTask: Task<Void, Never>?
    @ObservationIgnored private var bridges: [PlatformID: EgoBridge] = [:]

    var canDispatch: Bool {
        overallPhase != .running && !selectedPlatforms.isEmpty && !title.isEmpty && !markdown.isEmpty && !apiKey.isEmpty
    }

    func saveConfig() {
        UserDefaults.standard.set(apiKey, forKey: "deepseek.apiKey")
        UserDefaults.standard.set(model, forKey: "deepseek.model")
    }

    func log(_ line: String) {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        eventLog.append("[\(df.string(from: Date()))] \(line)")
        if eventLog.count > 300 { eventLog.removeFirst(eventLog.count - 300) }
    }

    func addAssets() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK {
            assetPaths.append(contentsOf: panel.urls.map { $0.path })
        }
    }

    // MARK: - 分发

    func dispatch() {
        saveConfig()
        guard canDispatch else { return }
        overallPhase = .running
        errorMessage = nil
        eventLog = []
        manualReceipt = ""
        for p in selectedPlatforms { platformPhase[p] = .running }

        let platforms = selectedPlatforms
        let html = MarkdownLite.render(markdown)
        let plain = MarkdownLite.plain(markdown)
        let tags = tagsText
            .split(whereSeparator: { $0.isWhitespace })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
            .filter { !$0.isEmpty }
        let assets = assetPaths

        runningTask = Task {
            defer { if overallPhase == .running { overallPhase = .draftReady } }
            for p in platforms {
                if Task.isCancelled { break }
                do {
                    try await runOnePlatform(p, html: html, plain: plain, tags: tags, assets: assets)
                } catch {
                    platformPhase[p] = .failed
                    log("【\(p.title)】✗ 异常：\(error.localizedDescription)")
                }
            }
            if platforms.allSatisfy({ platformPhase[$0] == .draftReady || platformPhase[$0] == .needLogin }) {
                log("全部平台处理完毕。请在 ego 浏览器逐个检查草稿并亲手发布（即刻的弹窗别关）。")
            }
        }
    }

    func runOnePlatform(_ p: PlatformID, html: String, plain: String, tags: [String], assets: [String]) async throws {
        let engine = try EgoLiteEngine()
        let bridge = try EgoBridge(spaceName: "publish post \(p.rawValue)-\(UUID().uuidString.prefix(6))", engine: engine)
        bridges[p] = bridge
        let loop = AgentLoop(llm: OpenAICompatClient(config: LLMConfig(
            baseURL: Self.defaultBaseURL, apiKey: apiKey, model: model)), bridge: bridge, maxSteps: 20)
        loop.onEvent = { [weak self] msg in
            Task { @MainActor in self?.log("【\(p.title)】\(msg)") }
        }

        log("【\(p.title)】调用 \(model) @ \(Self.defaultBaseURL)")
        let result = try await loop.run(goal: Self.goal(for: p, title: title, html: html, plain: plain, tags: tags, assets: assets))

        switch result.status {
        case "draftReady":
            platformPhase[p] = .draftReady
            log("【\(p.title)】✅ 草稿就绪：\(result.message)")
        case "needLogin":
            platformPhase[p] = .needLogin
            log("【\(p.title)】⚠️ 需要登录：请在 ego lite 打开\(p.title)登录后重试该平台")
        default:
            platformPhase[p] = .failed
            log("【\(p.title)】✗ 失败：\(result.message)")
        }
    }

    /// 平台作战地图：入口 + 内容形态 + 平台特有认知（契约由系统提示词统一约束）
    static func goal(for p: PlatformID, title: String, html: String, plain: String, tags: [String], assets: [String]) -> String {
        let tagText = tags.isEmpty ? "无" : tags.map { "#\($0)" }.joined(separator: " ")
        let imageInfo = assets.isEmpty ? "无图片" : "图片 \(assets.count) 张，本地路径：\(assets.joined(separator: "；"))"
        let opening = "把以下内容填入平台创作页，停在草稿状态（绝不点击发布/提交/发送类按钮）。\n- 标题：\(title)\n- 正文纯文本：\(plain.prefix(600))\n- \(imageInfo)\n"

        switch p {
        case .zhihu:
            return opening + """
                - 平台：知乎专栏（文章）。入口：https://zhuanlan.zhihu.com/write
                - 标题填入顶部标题输入框；正文用 paste_html 注入富文本编辑器，并把话题\(tagText == "无" ? "" : "（\(tagText)）")追加到正文结尾。
                - 完成后自检：标题框 value 与正文长度都符合预期。知乎会自动存草稿，不要碰右下角的发布按钮。
                - finish(status:"draftReady")。
                """
        case .x:
            return opening + """
                - 平台：X（动态，纯文本，上限 280 字符；标题并入第一行，超长请精简措辞，不要删关键信息）。
                - 入口：https://x.com/compose/post；若浏览器已打开 X 且弹出撰写窗，直接复用。
                - 正文填入撰写窗的文本区（contenteditable）。\(assets.isEmpty ? "" : "图片最多 4 张：把文件交给撰写窗自带的文件输入控件（upload）。")
                - 完成后自检文本已填入。停在撰写窗，不要点击"Post/发布"。
                - finish(status:"draftReady")。
                """
        case .jike:
            return opening + """
                - 平台：即刻（动态，纯文本）。入口：https://web.okjike.com
                - 在页面找到发布动态入口（带"发布/记录"字样的控件，点击后出现编辑弹窗），把正文填入弹窗编辑器，话题\(tagText == "无" ? "" : "（\(tagText)）")按平台习惯追加。
                - \(assets.isEmpty ? "无图片，跳过上传。" : "尝试把图片交给弹窗的上传控件；失败则跳过并在 message 中说明。")
                - 完成后停在弹窗（不要关闭弹窗，关闭会丢失内容），绝对不要点击弹窗中的"发布"。
                - finish(status:"draftReady")。
                """
        case .simFixture:
            let fixture = (try? Resources.url("fixture-page", ext: "html", sub: "Fixtures"))?.absoluteString ?? ""
            return opening + """
                - 平台：模拟平台（fixture，本地页面）。入口：\(fixture)
                - 标题填 input#title，正文 paste_html 到 #editor，图片 upload 到 input#files，话题填入 input#tags。
                - finish(status:"draftReady")。
                """
        default:
            return opening
        }
    }

    /// fixture 回执回读；真实平台请手动粘贴发布链接
    func readFixtureReceipt(for p: PlatformID) {
        guard let bridge = bridges[p] else { return }
        Task {
            do {
                let raw = try await bridge.evaluate(
                    js: "document.querySelector('#receipt') && document.querySelector('#receipt').dataset.url || ''")
                if let data = raw.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let url = obj["value"] as? String, !url.isEmpty {
                    manualReceipt = url
                    log("✅ 回执：\(url)")
                } else {
                    errorMessage = "未读取到回执：请在 fixture 页面点「确认发布」后重试"
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func reset() {
        runningTask?.cancel()
        overallPhase = .idle
        errorMessage = nil
        manualReceipt = ""
        for p in selectedPlatforms { platformPhase[p] = .idle }
    }
}

enum DispatchPhase: String {
    case idle = "待发布"
    case running = "分发中"
    case draftReady = "草稿就绪"
    case published = "已发布"
    case failed = "失败"
}

// MARK: - 界面

struct ContentView: View {
    @State private var model = AppModel()

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
            Button("添加图片…") { model.addAssets() }
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
                    let ph = model.platformPhase[p] ?? .idle
                    HStack(spacing: 4) {
                        Circle()
                            .fill(color(for: ph))
                            .frame(width: 8, height: 8)
                        Text("\(p.title) · \(ph.rawValue)").font(.caption)
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
                    model.dispatch()
                } label: {
                    Label(model.overallPhase == .running ? "分发中…" : "开始分发", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canDispatch)

                ForEach(model.selectedPlatforms.filter { $0 == .simFixture && (model.platformPhase[$0] == .draftReady) }, id: \.self) { p in
                    Button("读取 fixture 回执") { model.readFixtureReceipt(for: p) }
                        .buttonStyle(.bordered)
                }

                if model.overallPhase == .failed {
                    Button("重置") { model.reset() }
                        .buttonStyle(.bordered)
                }
                Spacer()
            }

            if let err = model.errorMessage {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.callout)
            }
            if model.overallPhase == .draftReady {
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

    private func color(for ph: PlatformPhase) -> Color {
        switch ph {
        case .idle: return .secondary
        case .running: return .blue
        case .draftReady: return .green
        case .needLogin: return .orange
        case .failed: return .red
        }
    }
}
