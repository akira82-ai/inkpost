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

struct InkBrand: View {
    var compact = true
    var body: some View {
        HStack(spacing: 8) {
            Text("墨").font(.custom("Songti SC", size: compact ? 17 : 20))
                .foregroundStyle(InkStyle.paper).frame(width: compact ? 27 : 32, height: compact ? 27 : 32)
                .background(InkStyle.ink, in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text("墨驿").font(InkStyle.font(compact ? 14 : 16)).tracking(2)
                Text(compact ? "INKPOST · 快速投递" : "INKPOST").font(InkStyle.font(9)).foregroundStyle(InkStyle.muted)
            }
        }.foregroundStyle(InkStyle.ink)
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
    var expanded = false
    let onImages: (Data) -> Void
    let onFiles: ([String]) -> Void
    @State private var editorHeight: CGFloat = 150
    @State private var resizeStart: CGFloat?
    @FocusState private var titleFocused: Bool
    private var editable: Bool { model.overallPhase == .pending }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    TextField("", text: $model.title)
                        .font(InkStyle.font(expanded ? 23 : 14, weight: .semibold)).textFieldStyle(.plain)
                        .focused($titleFocused).disabled(!editable)
                        .accessibilityLabel("标题，选填")
                    if model.title.isEmpty {
                        Text("标题（选填）")
                            .font(InkStyle.font(expanded ? 23 : 14))
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
                    PasteEditor(text: $model.markdown, enabled: editable, onImages: onImages, onFiles: onFiles)
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
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "line.3.horizontal").font(.system(size: 8)).foregroundStyle(InkStyle.placeholder)
                            .frame(width: 16, height: 16).contentShape(Rectangle())
                            .gesture(DragGesture().onChanged { value in
                                if resizeStart == nil { resizeStart = editorHeight }
                                editorHeight = min(expanded ? 480 : 300, max(expanded ? 240 : 150, (resizeStart ?? 150) + value.translation.height))
                            }.onEnded { _ in resizeStart = nil })
                            .accessibilityElement().accessibilityLabel("调整正文高度")
                            .accessibilityAdjustableAction { direction in
                                switch direction {
                                case .increment: editorHeight = min(expanded ? 480 : 300, editorHeight + 30)
                                case .decrement: editorHeight = max(expanded ? 240 : 150, editorHeight - 30)
                                @unknown default: break
                                }
                            }
                    }
            }.frame(height: editorHeight)
                .onAppear { if expanded { editorHeight = 270 } }

        }.foregroundStyle(InkStyle.ink)
    }
}

struct PasteEditor: NSViewRepresentable {
    @Binding var text: String
    let enabled: Bool
    let onImages: (Data) -> Void
    let onFiles: ([String]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        let editor = ImagePasteTextView(frame: NSRect(x: 0, y: 0, width: 384, height: 150))
        editor.delegate = context.coordinator; editor.isRichText = false
        editor.font = NSFont(name: "Avenir Next", size: 13) ?? .systemFont(ofSize: 13)
        editor.textColor = NSColor(red: 37/255, green: 41/255, blue: 35/255, alpha: 1)
        editor.drawsBackground = false
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
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PasteEditor
        init(_ parent: PasteEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            if let view = notification.object as? NSTextView { parent.text = view.string }
        }
    }
}

final class ImagePasteTextView: NSTextView {
    var onImages: ((Data) -> Void)?
    var onFiles: (([String]) -> Void)?
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
                AttachmentTile(data: model.assetData[path], name: URL(fileURLWithPath: path).lastPathComponent,
                    editable: editable, dragging: dragging == path,
                    open: { preview = path }, remove: { controller.removeAsset(path) })
                    .overlay {
                        if dropTarget == path {
                            RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0x8A9779), lineWidth: 2).padding(-3).allowsHitTesting(false)
                        }
                    }
                    .onDrag {
                        guard editable else { return NSItemProvider() }
                        dragging = path
                        return NSItemProvider(object: path as NSString)
                    }
                    .onDrop(of: [.text], delegate: ImageOrderDrop(target: path, dragging: $dragging, dropTarget: $dropTarget, editable: editable, move: controller.moveAsset))
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
        .onHover { _ in if NSEvent.pressedMouseButtons == 0 { dragging = nil; dropTarget = nil } }
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
    private func chooseImages() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = true
        panel.begin { response in if response == .OK { controller.addAssets(panel.urls.map(\.path)) } }
    }
}
private struct PreviewAsset: Identifiable { let path: String; var id: String { path } }

private struct AttachmentTile: View {
    let data: Data?
    let name: String
    let editable: Bool
    let dragging: Bool
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

private struct ImageOrderDrop: DropDelegate {
    let target: String
    @Binding var dragging: String?
    @Binding var dropTarget: String?
    let editable: Bool
    let move: (String, String) -> Void
    func validateDrop(info: DropInfo) -> Bool { editable && dragging != nil }
    func dropEntered(info: DropInfo) { if editable && dragging != nil { dropTarget = target } }
    func dropExited(info: DropInfo) { if dropTarget == target { dropTarget = nil } }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        guard editable, let source = dragging else { return false }
        move(source, target); dragging = nil; dropTarget = nil; return true
    }
}

struct ChannelPresentation: Identifiable {
    let id: String
    let platform: PlatformID?
    let name: String
    let badge: String
    let tone: UInt32
    var available: Bool { platform?.isAvailable == true }
    static let all: [Self] = [
        .init(id: "zhihu", platform: .zhihu, name: "知乎", badge: "知", tone: 0x3C78B6),
        .init(id: "jike", platform: .jike, name: "即刻", badge: "即", tone: 0xC6A344),
        .init(id: "x", platform: .x, name: "X", badge: "𝕏", tone: 0x31332F),
        .init(id: "weibo", platform: .weibo, name: "微博", badge: "微", tone: 0xD85B43),
        .init(id: "juejin", platform: .juejin, name: "掘金沸点", badge: "掘", tone: 0x1E80FF),
        .init(id: "xiaohongshu", platform: .xiaohongshu, name: "小红书", badge: "红", tone: 0xBF6256),
        .init(id: "threads", platform: nil, name: "Threads", badge: "@", tone: 0x44473F),
        .init(id: "linkedin", platform: nil, name: "LinkedIn", badge: "in", tone: 0x3776A1),
        .init(id: "medium", platform: nil, name: "Medium", badge: "M", tone: 0x43473D),
        .init(id: "bluesky", platform: nil, name: "Bluesky", badge: "B", tone: 0x4B8FCB),
        .init(id: "instagram", platform: nil, name: "Instagram", badge: "◎", tone: 0xAF637C)
    ]
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
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(ChannelPresentation.all) { channel in
                Button {
                    if channel.available, let platform = channel.platform { controller.select(platform) }
                    else { model.notice = "\(channel.name) 尚未适配，暂不可选" }
                } label: {
                    HStack(spacing: 4) { ChannelBadge(channel: channel); Text(channel.name).font(InkStyle.font(11)).fixedSize() }
                        .padding(.horizontal, 4).frame(height: 32).frame(maxWidth: .infinity)
                        .background(channel.isSelected(in: model) ? InkStyle.selected : .clear, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(channel.isSelected(in: model) ? InkStyle.selectedLine : InkStyle.line))
                        .contentShape(RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain).foregroundStyle(InkStyle.ink)
                    .disabled(model.overallPhase != .pending)
                    .help(channel.available ? channel.name : "\(channel.name) 待适配，暂不可选")
                    .accessibilityLabel(channel.available ? channel.name : "\(channel.name)，待适配")
                    .accessibilityAddTraits(channel.isSelected(in: model) ? .isSelected : [])
            }
        }.transaction { $0.animation = nil }
    }
}

struct DispatchAction: View {
    let model: DispatchModel
    let controller: DispatchController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    private var filling: Bool { model.overallPhase == .preparing }
    private var title: String {
        switch model.overallPhase {
        case .pending: return "填写到所选渠道"
        case .preparing: return "正在填写 · \(model.currentPlatform?.title ?? "所选渠道")"
        case .awaitingConfirm: return "已填好，前往确认并发布 ↗"
        default: return "前往处理 ↗"
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
                if filling {
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
        }.buttonStyle(.plain).disabled(filling || model.isHandingOff)
            .animation(reduceMotion ? nil : .timingCurve(0.2, 0.7, 0.3, 1, duration: 0.42), value: model.currentPlatform)
            .accessibilityLabel(title)
    }
    private func act() {
        guard model.overallPhase == .pending else { controller.openWorkspace(); return }
        guard controller.canDispatch else { model.notice = "请填写正文并至少选择一个渠道；标题和图片可不填"; return }
        controller.dispatch()
    }
}

struct DispatchStatus: View {
    let model: DispatchModel
    private var message: String {
        switch model.overallPhase {
        case .pending:
            return "选好渠道后，开始填写。"
        case .preparing:
            let index = model.currentPlatform.flatMap { model.taskPlatforms.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            return "正在填写 \(index)/\(model.taskPlatforms.count) 个渠道，可以先忙别的，完成后我会提醒你"
        case .cancelled:
            return "已停止填写，内容已保留。正在执行的浏览器操作可能已完成，请先检查页面。"
        case .awaitingConfirm:
            return "全部已填好。请前往浏览器检查，并亲手点击发布；墨驿的填写任务已完成。"
        default:
            return "部分渠道遇到问题，需要您前往浏览器手工处理。已填好的内容会保留，处理后可继续。"
        }
    }
    var body: some View {
        Text(message).font(InkStyle.font(10)).foregroundStyle(InkStyle.muted)
            .multilineTextAlignment(.center).lineSpacing(4)
            .frame(maxWidth: .infinity).fixedSize(horizontal: false, vertical: true)
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
