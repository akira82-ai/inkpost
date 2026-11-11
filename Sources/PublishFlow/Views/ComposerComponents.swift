import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PublishKit

// Logical point values and colors from the approved HTML specification.
enum InkStyle {
    static let paper = Color(hex: 0xFCFBF7)
    static let ink = Color(hex: 0x252923)
    static let muted = Color(hex: 0x85877E)
    static let placeholder = Color(hex: 0xA1A596)
    static let line = Color(hex: 0xE8E7DF)
    static let selected = Color(hex: 0xDCE3D3)
    static let selectedLine = Color(hex: 0xC3CCBA)
    static let warning = Color(hex: 0xAA7850)
    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Avenir Next", size: size).weight(weight)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}

struct QuietIcon: View {
    let symbol: String
    let label: String
    var size: CGFloat = 26
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size == 30 ? 17 : 15, weight: .regular))
                .foregroundStyle(Color(hex: size == 30 ? 0x767F6D : 0xA5A99C))
                .frame(width: size, height: size)
                .background(hovered ? Color(hex: 0xECEEE5) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovered = $0 }.help(label).accessibilityLabel(label)
    }
}

struct ComposerFields: View {
    @Bindable var model: DispatchModel
    var bodyFocusRequest: UUID?
    let onImages: (Data) -> Void
    let onFiles: ([String]) -> Void
    @FocusState private var titleFocused: Bool
    private var editable: Bool { model.overallPhase == .pending }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    TextField("", text: $model.title)
                        .font(InkStyle.font(14, weight: .semibold)).textFieldStyle(.plain)
                        .focused($titleFocused).disabled(!editable)
                        .accessibilityLabel("标题，选填")
                    if model.title.isEmpty {
                        Text("标题（选填）")
                            .font(InkStyle.font(14))
                            .foregroundStyle(InkStyle.placeholder)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                QuietIcon(symbol: "xmark", label: "清空标题") { model.title = ""; titleFocused = true }
                    .opacity(model.title.isEmpty ? 0 : 1).disabled(model.title.isEmpty || !editable)
                    .accessibilityHidden(model.title.isEmpty).frame(width: 30)
            }.padding(.vertical, 9)
            Rectangle().fill(Color(hex: 0xEEEEE6)).frame(height: 1).padding(.bottom, 12)
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    PasteEditor(text: $model.markdown, enabled: editable, onImages: onImages, onFiles: onFiles, focusRequest: bodyFocusRequest)
                    if model.markdown.isEmpty {
                        Text("正文（必填），支持换行和 emoji；图片选填…")
                            .font(InkStyle.font(13)).foregroundStyle(InkStyle.placeholder)
                            .lineSpacing(6).padding(.top, 5).allowsHitTesting(false)
                    }
                }.frame(maxHeight: .infinity)
                HStack(spacing: 0) {
                    Button { model.markdown = "" } label: {
                        Text("清空").font(InkStyle.font(10))
                            .foregroundStyle(model.markdown.isEmpty || !editable ? Color(hex: 0xC4C7BD) : InkStyle.muted)
                            .frame(minWidth: 34, minHeight: 26).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(model.markdown.isEmpty || !editable)
                        .accessibilityLabel("清空正文")
                    Spacer(minLength: 0)
                    Text("\(model.markdown.count) 字").font(InkStyle.font(10)).monospacedDigit()
                        .foregroundStyle(InkStyle.placeholder).padding(.horizontal, 4).padding(.trailing, 20)
                }.frame(height: 30).background(InkStyle.paper)

            // Six 23.4pt lines plus text insets; the 30pt footer never scrolls.
            }.frame(height: ceil(6 * 23.4 + 10) + 30)

        }.foregroundStyle(InkStyle.ink)
    }
}

struct PasteEditor: NSViewRepresentable {
    @Binding var text: String
    let enabled: Bool
    let onImages: (Data) -> Void
    let onFiles: ([String]) -> Void
    var focusRequest: UUID?
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        let editor = ImagePasteTextView(frame: NSRect(x: 0, y: 0, width: 384, height: 150))
        editor.delegate = context.coordinator; editor.isRichText = false
        editor.font = NSFont(name: "Avenir Next", size: 13) ?? .systemFont(ofSize: 13)
        editor.textColor = NSColor(red: 37/255, green: 41/255, blue: 35/255, alpha: 1)
        editor.drawsBackground = false
        editor.focusRingType = .none
        editor.insertionPointColor = editor.textColor ?? .textColor
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]; editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.lineFragmentPadding = 0
        // The footer is a separate sibling of the scrolling editor.
        editor.textContainerInset = NSSize(width: 0, height: 5)
        editor.textContainer?.lineFragmentPadding = 0
        let paragraph = NSMutableParagraphStyle()
        // Use inter-line spacing rather than stretching the font line box and caret.
        paragraph.lineSpacing = max(0, 23.4 - (editor.layoutManager?.defaultLineHeight(for: editor.font!) ?? 18))
        editor.defaultParagraphStyle = paragraph
        editor.typingAttributes = [.font: editor.font!, .paragraphStyle: paragraph, .foregroundColor: editor.textColor!]
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? ImagePasteTextView else { return }
        if editor.string != text { editor.string = text }
        editor.isEditable = enabled; editor.onImages = onImages; editor.onFiles = onFiles
        editor.needsLayout = true
        if enabled, let focusRequest, context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            editor.requestBodyFocus()
        }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PasteEditor
        var lastFocusRequest: UUID?
        init(_ parent: PasteEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            if let view = notification.object as? NSTextView { parent.text = view.string }
        }
    }
}

final class ImagePasteTextView: NSTextView {
    var onImages: ((Data) -> Void)?
    var onFiles: (([String]) -> Void)?
    private var pendingBodyFocus = false
    func requestBodyFocus() {
        pendingBodyFocus = true
        schedulePendingBodyFocus()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // AppKit is still attaching the view here; never reorder/activate its window synchronously.
        schedulePendingBodyFocus()
    }
    private func schedulePendingBodyFocus() {
        DispatchQueue.main.async { [weak self] in self?.applyPendingBodyFocus() }
    }
    private func applyPendingBodyFocus() {
        guard pendingBodyFocus, isEditable, let window else { return }
        // Consume before entering AppKit, whose callbacks can re-enter the view lifecycle.
        pendingBodyFocus = false
        window.makeFirstResponder(self)
    }
    private static let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, .init(UTType.jpeg.identifier)]
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        [.fileURL] + Self.imageTypes + super.readablePasteboardTypes.filter { !Self.imageTypes.contains($0) && $0 != .fileURL }
    }
    override func readSelection(from pasteboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard isEditable else { return false }
        if type == .fileURL {
            let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true, .urlReadingContentsConformToTypes: [UTType.image.identifier]]
            guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL], !urls.isEmpty, let onFiles else { return false }
            onFiles(urls.map(\.path)); return true
        }
        if Self.imageTypes.contains(type) {
            guard let data = pasteboard.data(forType: type), let onImages else { return false }
            onImages(data); return true
        }
        return super.readSelection(from: pasteboard, type: type)
    }
}

struct AttachmentStrip: View {
    let model: DispatchModel
    let controller: DispatchController
    @State private var dragging: String?
    @State private var dropTarget: String?
    @State private var preview: String?
    private var editable: Bool { model.overallPhase == .pending }
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 0) {
            ForEach(model.assetPaths, id: \.self) { path in
                AttachmentTile(path: path, data: model.assetData[path],
                    editable: editable, dragging: dragging == path,
                    dragStarted: { dragging = path; dropTarget = nil }, dragEnded: clearDrag,
                    accepts: { model.overallPhase == .pending && model.assetPaths.contains($0) && model.assetPaths.contains(path) },
                    targeted: { value in
                        if value { dropTarget = path }
                        else if dropTarget == path { dropTarget = nil }
                    },
                    dropped: { source in controller.moveAsset(source, before: path); clearDrag() },
                    open: { preview = path }, remove: { controller.removeAsset(path) })
                    .overlay(alignment: .leading) {
                        if dropTarget == path {
                            Capsule().fill(Color(hex: 0x8A9779)).frame(width: 2).offset(x: -5).allowsHitTesting(false)
                        }
                    }
            }
            if model.assetPaths.count < 6 {
                Button(action: chooseImages) {
                    Image(systemName: "plus").font(.system(size: 25, weight: .ultraLight))
                        .foregroundStyle(Color(hex: 0x939C87)).frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(hex: 0xF2F3EC), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(hex: 0xC9CDBF), style: StrokeStyle(lineWidth: 1, dash: [4])))
                        .aspectRatio(1, contentMode: .fit).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(!editable).help("图片选填，最多 6 张").accessibilityLabel("添加图片")
            }
        }.padding(.vertical, 7)
        .onChange(of: editable) { _, value in if !value { clearDrag() } }
        .onChange(of: model.assetPaths) { _, paths in
            if let dragging, !paths.contains(dragging) { clearDrag() }
        }
        .onDisappear(perform: clearDrag)
        .sheet(item: Binding(get: { preview.map(PreviewAsset.init) }, set: { preview = $0?.path })) { item in
            ZStack(alignment: .topTrailing) {
                Color(hex: 0x20271F)
                if let image = model.assetData[item.path].flatMap(NSImage.init(data:)) {
                    Image(nsImage: image).resizable().scaledToFit().padding(40)
                }
                QuietIcon(symbol: "xmark", label: "关闭图片预览", size: 30) { preview = nil }.padding(12)
            }.frame(minWidth: 560, minHeight: 420).onExitCommand { preview = nil }
        }
    }
    private func clearDrag() { dragging = nil; dropTarget = nil }
    private func chooseImages() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = true
        panel.begin { response in if response == .OK { controller.addAssets(panel.urls.map(\.path)) } }
    }
}
private struct PreviewAsset: Identifiable { let path: String; var id: String { path } }

private struct AttachmentTile: View {
    let path: String
    let data: Data?
    private var name: String { URL(fileURLWithPath: path).lastPathComponent }
    let editable: Bool
    let dragging: Bool
    let dragStarted: () -> Void
    let dragEnded: () -> Void
    let accepts: (String) -> Bool
    let targeted: (Bool) -> Void
    let dropped: (String) -> Void
    let open: () -> Void
    let remove: () -> Void
    @State private var hovered = false
    @FocusState private var focused: Bool
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: open) {
                GeometryReader { geometry in
                    if let image = data.flatMap(NSImage.init(data:)) {
                        Image(nsImage: image).resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    }
                }.background(Color(hex: 0xEEEEE7)).clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(InkStyle.ink.opacity(0.07)))
            }.buttonStyle(.plain).focused($focused).accessibilityLabel("预览图片 \(name)")
                .overlay {
                    AttachmentDragSource(path: path, data: data, editable: editable,
                        started: dragStarted, ended: dragEnded, clicked: { focused = true; open() },
                        removed: remove, hovered: { hovered = $0 },
                        accepts: accepts, targeted: targeted, dropped: dropped)
                        .accessibilityHidden(true)
                }
            if editable {
                Button(action: remove) {
                    Image(systemName: "xmark").font(.system(size: 9))
                        .foregroundStyle(Color(hex: 0x4E5648)).frame(width: 19, height: 19)
                        .background(InkStyle.paper.opacity(0.92), in: Circle()).shadow(color: .black.opacity(0.13), radius: 2, y: 1)
                }.buttonStyle(.plain).padding(2).help("移除图片")
                    .opacity(hovered || focused ? 1 : 0)
                    .accessibilityLabel("移除图片 \(name)")
                    .accessibilityHidden(!hovered && !focused)
            }
        }.aspectRatio(1, contentMode: .fit)
            .opacity(dragging ? 0.35 : 1).scaleEffect(dragging ? 0.94 : 1)
            .onHover { hovered = $0 }
    }
}

struct ChannelPresentation: Identifiable {
    let id: String
    let platform: PlatformID?
    let name: String
    let badge: String
    let tone: UInt32
    var available: Bool { platform?.isAvailable == true }
    static let all: [Self] = {
        let styled: [Self] = [
            .init(id: "zhihu", platform: .zhihu, name: "知乎", badge: "知", tone: 0x3C78B6),
            .init(id: "jike", platform: .jike, name: "即刻", badge: "即", tone: 0xC6A344),
            .init(id: "x", platform: .x, name: "X", badge: "𝕏", tone: 0x31332F),
            .init(id: "weibo", platform: .weibo, name: "微博", badge: "微", tone: 0xD85B43),
            .init(id: "juejin", platform: .juejin, name: "掘金沸点", badge: "掘", tone: 0x1E80FF),
            .init(id: "bilibili", platform: .bilibili, name: "B站动态", badge: "B", tone: 0x1682A6)
        ]
        let styledPlatforms = Set(styled.compactMap(\.platform))
        return styled + PlatformID.allCases.filter { $0 != .simFixture && !styledPlatforms.contains($0) }.map {
            Self(id: $0.id, platform: $0, name: $0.title, badge: String($0.title.prefix(1)), tone: 0x44473F)
        }
    }()
    @MainActor func isSelected(in model: DispatchModel) -> Bool { platform.map { model.selectedPlatforms.contains($0) } ?? false }
}
struct ChannelBadge: View {
    let channel: ChannelPresentation
    var size: CGFloat = 17
    var body: some View {
        Text(channel.badge).font(InkStyle.font(size == 17 ? 10 : 14, weight: .semibold))
            .foregroundStyle(.white).frame(width: size, height: size)
            .background(Color(hex: channel.tone), in: RoundedRectangle(cornerRadius: size == 17 ? 4 : 7))
    }
}

struct ChannelGrid: View {
    let model: DispatchModel
    let controller: DispatchController
    private var editing: Bool { model.overallPhase == .pending }
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(ChannelPresentation.all.filter(\.available)) { channel in
                Group {
                    if editing {
                        Button {
                            if let platform = channel.platform { controller.select(platform) }
                        } label: { label(channel) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(channel.name)
                        .accessibilityAddTraits(channel.isSelected(in: model) ? .isSelected : [])
                    } else {
                        label(channel)
                    }
                }
                .foregroundStyle(InkStyle.ink)
                .background(channel.isSelected(in: model) ? InkStyle.selected : .clear, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(channel.isSelected(in: model) ? InkStyle.selectedLine : InkStyle.line))
            }
        }.transaction { $0.animation = nil }
    }

    private func label(_ channel: ChannelPresentation) -> some View {
        HStack(spacing: 4) {
            ChannelBadge(channel: channel)
            Text(channel.name).font(InkStyle.font(11)).lineLimit(1).frame(maxWidth: .infinity)
            if !editing, let platform = channel.platform, model.taskPlatforms.contains(platform),
               let phase = model.platformPhase[platform] {
                statusIcon(ChannelStatusPresentation(phase: phase), platform: platform)
            }
        }.padding(.horizontal, 6).frame(height: 36).frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }

    @ViewBuilder private func statusIcon(_ status: ChannelStatusPresentation, platform: PlatformID) -> some View {
        if status.canOpen {
            Button { controller.openChannel(platform) } label: {
                Image(systemName: status.symbol).font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 26).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(Color(hex: status == .login ? 0x977126 : 0xA16C42))
                .disabled(model.isHandingOff || model.isSettling)
                .help("\(platform.title)：\(status.title)，点击前往对应页面")
                .accessibilityLabel("\(platform.title)，\(status.title)，前往对应页面")
        } else if status == .filling {
            ProgressView().controlSize(.mini).frame(width: 24, height: 26)
                .help("\(platform.title)：\(status.title)")
                .accessibilityLabel("\(platform.title)，\(status.title)")
        } else {
            Image(systemName: status.symbol).font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: 0x567749)).frame(width: 24, height: 26)
                .help("\(platform.title)：\(status.title)")
                .accessibilityLabel("\(platform.title)，\(status.title)")
        }
    }
}

struct DispatchAction: View {
    let model: DispatchModel
    let controller: DispatchController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    private var filling: Bool { model.overallPhase == .preparing }
    private var title: String {
        if model.isHandingOff { return "正在打开…" }
        if model.isSettling { return "正在交还浏览器…" }
        switch model.overallPhase {
        case .pending: return "发布"
        case .preparing: return "正在填写 · \(model.currentPlatform?.title ?? "所选渠道")"
        case .needLogin: return "我已登录，继续"
        case .awaitingConfirm: return "已填写，需要你手工发布"
        default: return "去查看"
        }
    }
    var body: some View {
        Button(action: act) {
            HStack(spacing: 9) {
                if filling {
                    Circle().fill(Color(hex: 0xCEDBBF)).frame(width: 5, height: 5)
                        .opacity(reduceMotion || !pulse ? 1 : 0.3).scaleEffect(reduceMotion || !pulse ? 1 : 0.7)
                        .onAppear { pulse = true }.onDisappear { pulse = false }
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.65).repeatForever(autoreverses: true), value: pulse)
                }
                if filling && !model.isSettling {
                    HStack(spacing: 6) {
                        Text("正在填写 ·")
                        Text(model.currentPlatform?.title ?? "所选渠道")
                            .id(model.currentPlatform)
                            .transition(reduceMotion ? .identity : .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                    }.frame(height: 20).clipped()
                } else {
                    Text(title).frame(height: 20)
                }
            }.font(InkStyle.font(12, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.horizontal, 12).frame(height: 42).clipped()
                .foregroundStyle(InkStyle.paper).background(InkStyle.ink, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).disabled(filling || model.isHandingOff || model.isSettling)
            .animation(reduceMotion ? nil : .timingCurve(0.2, 0.7, 0.3, 1, duration: 0.42), value: model.currentPlatform)
            .accessibilityLabel(title)
    }
    private func act() {
        if model.overallPhase == .needLogin { controller.resumeWaitingLogins(); return }
        guard model.overallPhase == .pending else { controller.openTaskDestination(); return }
        guard controller.canDispatch else { model.notice = "请填写正文并至少选择一个渠道；标题和图片可不填"; return }
        controller.dispatch()
    }
}

struct DispatchStatus: View {
    let model: DispatchModel
    private var message: String {
        switch model.overallPhase {
        case .pending:
            return "填好后由你确认发布。"
        case .preparing:
            let index = model.currentPlatform.flatMap { model.taskPlatforms.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            return "正在填写 \(index)/\(model.taskPlatforms.count) 个渠道，可以先忙别的，完成后我会提醒你"
        case .needLogin:
            let ready = model.taskPlatforms.filter { model.platformPhase[$0] == .awaitingConfirm }.count
            return "\(ready) 个已填好 · \(model.waitingLoginPlatforms.count) 个待登录"
        case .awaitingConfirm:
            return "\(model.taskPlatforms.count) 个渠道已填好，请确认后手工发布。"
        default:
            let attention = model.attentionPlatforms
            let readyCount = model.taskPlatforms.count - attention.count
            if model.overallPhase == .cancelled { return "已停止填写，内容已保留，请检查页面。" }
            guard !attention.isEmpty else { return "填写已结束，请检查页面。" }
            if readyCount == 0 { return "\(attention.count) 个渠道需处理" }
            return "\(readyCount) 个已填好 · \(attention.map(\.title).joined(separator: "、"))需处理"
        }
    }
    var body: some View {
        Text(message).font(InkStyle.font(11)).foregroundStyle(InkStyle.muted)
            .multilineTextAlignment(.center).lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct NoticeOverlay: ViewModifier {
    @Bindable var model: DispatchModel
    func body(content: Content) -> some View {
        content.overlay {
            if let notice = model.notice {
                Text(notice).font(InkStyle.font(12)).lineSpacing(5).multilineTextAlignment(.center)
                    .padding(.horizontal, 18).padding(.vertical, 13).foregroundStyle(InkStyle.paper)
                    .background(InkStyle.ink.opacity(0.93), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.07)))
                    .shadow(color: InkStyle.ink.opacity(0.13), radius: 12, y: 6).padding(20).allowsHitTesting(false)
                    .accessibilityAddTraits(.updatesFrequently)
                    .task(id: notice) {
                        do { try await Task.sleep(for: .seconds(2.4)) } catch { return }
                        if model.notice == notice { model.notice = nil }
                    }
            }
        }
    }
}
