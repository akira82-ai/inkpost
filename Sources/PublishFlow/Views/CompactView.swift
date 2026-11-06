import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PublishKit

private enum InkStyle {
    static let paper = Color(red: 0.988, green: 0.984, blue: 0.969)
    static let ink = Color(red: 0.145, green: 0.161, blue: 0.137)
    static let selected = Color(red: 0.863, green: 0.890, blue: 0.827)
}

struct CompactView: View {
    @Bindable var model: DispatchModel
    let controller: DispatchController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragging: String?
    @State private var preview: String?
    @State private var resizeStart: CGFloat?
    @State private var editorHeight: CGFloat = 150
    private var editing: Bool { model.overallPhase == .pending }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header.padding(.bottom, 16)
                HStack {
                    TextField("给这次分享起个标题", text: $model.title)
                        .textFieldStyle(.plain).font(.system(size: 14, weight: .semibold))
                    clearButton(model.title) { model.title = "" }
                }.padding(.vertical, 9).disabled(!editing)
                Divider().padding(.bottom, 12)
                ZStack(alignment: .bottomTrailing) {
                    PasteEditor(text: $model.markdown, enabled: editing, onImages: controller.pasteImage)
                        .frame(height: editorHeight)
                    if model.markdown.isEmpty {
                        VStack { HStack { Text("有什么想分享的？支持 Markdown，也可粘贴图片…")
                            .font(.system(size: 13)).foregroundStyle(.secondary); Spacer() }; Spacer() }
                            .padding(.top, 5).allowsHitTesting(false)
                    }
                    VStack { HStack { Spacer(); clearButton(model.markdown) { model.markdown = "" } }; Spacer() }
                        .disabled(!editing)
                    Text("\(model.markdown.count) 字").font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.secondary).padding(4).background(InkStyle.paper).padding(.trailing, 16).padding(.bottom, 5)
                    Image(systemName: "line.3.horizontal").font(.system(size: 8)).foregroundStyle(.tertiary)

                        .gesture(DragGesture().onChanged { value in if resizeStart == nil { resizeStart = editorHeight }; editorHeight = min(300, max(150, (resizeStart ?? 150) + value.translation.height)) }.onEnded { _ in resizeStart = nil })
                }
                images.padding(.top, 10).padding(.bottom, 15)
                HStack { Text("投递到"); Spacer(); Text("\(model.selectedPlatforms.count) 个渠道") }
                    .font(.system(size: 10)).foregroundStyle(.secondary).padding(.bottom, 8)
                ChannelGrid(model: model, controller: controller).disabled(!editing)
                if !editing { status.padding(.top, 14) }
                Divider().padding(.top, 15).padding(.bottom, 11)
                Button(action: primaryAction) {
                    HStack(spacing: 8) {
                        if model.overallPhase == .preparing {
                            ProgressView().controlSize(.mini).tint(.white)
                            Text("正在填写\(model.currentPlatform?.title ?? "所选渠道")…")
                                .id(model.currentPlatform).transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                        } else { Text(actionTitle) }
                    }
                    .font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 42)
                    .clipped().foregroundStyle(.white).background(InkStyle.ink).clipShape(RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).disabled(model.overallPhase == .preparing)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.42), value: model.currentPlatform)
                Text("最终发布由你确认").font(.system(size: 10)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.top, 9)
                if model.overallPhase == .awaitingConfirm {
                    Button("开始新一份") { controller.newDraft() }.buttonStyle(.plain).font(.caption).padding(.top, 10)
                }
                if model.overallPhase == .failed {
                    Button("修改未完成渠道的内容") { controller.editUnfinishedChannels() }.buttonStyle(.plain).font(.caption).padding(.top, 10)
                }
                if let error = model.errorMessage { Text(error).font(.caption).foregroundStyle(.orange).padding(.top, 8) }
            }.padding(18)
        }
        .frame(width: 420, height: popoverHeight)
        .background(InkStyle.paper)
        .overlay {
            if let notice = model.notice {
                Text(notice).font(.system(size: 12)).padding(14).foregroundStyle(.white)
                    .background(InkStyle.ink.opacity(0.95), in: RoundedRectangle(cornerRadius: 9))
                    .padding(24).allowsHitTesting(false)
                    .task(id: notice) { try? await Task.sleep(for: .seconds(2.4)); if model.notice == notice { model.notice = nil } }
            }
        }
        .sheet(item: Binding(get: { preview.map(PreviewAsset.init) }, set: { preview = $0?.path })) { item in
            VStack { if let image = model.assetData[item.path].flatMap(NSImage.init(data:)) { Image(nsImage: image).resizable().scaledToFit() }; Button("关闭") { preview = nil } }
                .padding(20).frame(minWidth: 500, minHeight: 400)
        }
    }
    private var popoverHeight: CGFloat {
        let issues = model.taskPlatforms.filter { [.failed, .needLogin].contains(model.platformPhase[$0] ?? .pending) }.count
        let height = 552 + (editorHeight - 150) + (editing ? 0 : 55 + CGFloat(issues) * 65)
        return min(height, (NSScreen.main?.visibleFrame.height ?? 800) - 60)
    }
    private var header: some View {
        HStack(spacing: 8) {
            Text("墨").font(.custom("Songti SC", size: 18)).foregroundStyle(.white).frame(width: 27, height: 27).background(InkStyle.ink, in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) { Text("墨驿").font(.system(size: 14)); Text("INKPOST · 快速投递").font(.system(size: 9)).foregroundStyle(.secondary) }
            Spacer()
            Menu {
                Button("完整界面") { openWindow(id: "workspace"); NSApp.activate(ignoringOtherApps: true) }
                Divider()
                Button("退出墨驿") { NSApp.terminate(nil) }
            } label: { Image(systemName: "ellipsis").foregroundStyle(.secondary) }.menuStyle(.borderlessButton).fixedSize().help("更多")
            Button { openWindow(id: "workspace"); NSApp.activate(ignoringOtherApps: true); dismiss() } label: { Image(systemName: "arrow.up.right.square").font(.system(size: 17)).frame(width: 30, height: 30) }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("打开完整界面")
        }
    }
    private func clearButton(_ value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: "xmark.circle").font(.system(size: 13)).foregroundStyle(.tertiary).frame(width: 26, height: 26) }
            .buttonStyle(.plain).opacity(value.isEmpty ? 0 : 1).disabled(value.isEmpty).help("清空")
    }
    private var images: some View {
        GeometryReader { geo in
            let size = (geo.size.width - 40) / 6
            HStack(spacing: 8) {
                ForEach(model.assetPaths, id: \.self) { path in
                    ZStack(alignment: .topTrailing) {
                        Button { preview = path } label: {
                            if let image = model.assetData[path].flatMap(NSImage.init(data:)) { Image(nsImage: image).resizable().scaledToFill().frame(width: size, height: size).clipped() }
                        }.buttonStyle(.plain)
                        if editing {
                            Button { controller.removeAsset(path) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .black.opacity(0.6)) }.buttonStyle(.plain).padding(2)
                        }
                    }.frame(width: size, height: size).background(.quaternary).clipShape(RoundedRectangle(cornerRadius: 8))
                        .onDrag { dragging = path; return NSItemProvider(object: path as NSString) }
                        .onDrop(of: [.text], isTargeted: nil) { _ in guard let dragging else { return false }; controller.moveAsset(dragging, before: path); self.dragging = nil; return true }
                }
                if model.assetPaths.count < 6 {
                    Button(action: chooseImages) { Image(systemName: "plus").font(.system(size: 23, weight: .ultraLight)).foregroundStyle(.secondary).frame(width: size, height: size).background(Color.gray.opacity(0.04)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.gray.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))) }.buttonStyle(.plain).disabled(!editing)
                }
            }
        }.frame(height: 58)
    }
    private func chooseImages() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = true
        panel.begin { response in if response == .OK { controller.addAssets(panel.urls.map(\.path)) } }
    }
    private var actionTitle: String {
        switch model.overallPhase {
        case .pending: return "填写到所选渠道"
        case .preparing: return "正在填写…"
        case .awaitingConfirm: return "已填好，前往确认并发布 ↗"
        default: return "前往处理 ↗"
        }
    }
    private func primaryAction() {
        if editing {
            guard !model.apiKey.isEmpty else { model.notice = "请在完整界面配置 API Key"; return }
            guard controller.canDispatch else { model.notice = "请选择渠道并填写内容；文章渠道还需要标题"; return }
            controller.dispatch()
        } else { controller.openWorkspace() }
    }
    private var status: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.overallPhase == .preparing {
                let index = model.currentPlatform.flatMap { model.taskPlatforms.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
                Text("正在填写 \(index)/\(model.taskPlatforms.count) 个渠道，可以先忙别的，完成后我会提醒你")
            } else if model.overallPhase == .awaitingConfirm { Text("全部已填好，请检查内容并亲手发布。") }
            else { Text("需要您手工处理") }
            ForEach(model.taskPlatforms.filter { [.failed, .needLogin].contains(model.platformPhase[$0] ?? .pending) }) { platform in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(platform.title)：\(model.platformMessages[platform] ?? "请到浏览器检查")")
                    Button("已处理，继续 \(platform.title)") { controller.resume(platform) }.disabled(model.overallPhase == .preparing)
                }
            }
        }.font(.system(size: 11)).foregroundStyle(.secondary)
    }
}
private struct PreviewAsset: Identifiable { let path: String; var id: String { path } }

private struct ChannelGrid: View {
    let model: DispatchModel
    let controller: DispatchController
    var body: some View {
        GeometryReader { geometry in
            let unit = (geometry.size.width - 40) / 6
            let rows = rows(unit: unit)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rows.indices, id: \.self) { index in
                    HStack(spacing: 8) {
                        ForEach(rows[index], id: \.0) { platform, span in
                            Button { controller.select(platform) } label: {
                                HStack(spacing: 4) { Text(platform == .x ? "𝕏" : String(platform.title.prefix(1))).font(.system(size: 10, weight: .bold)).frame(width: 17, height: 17).foregroundStyle(.white).background(platform == .zhihu ? Color.blue : Color.gray, in: RoundedRectangle(cornerRadius: 4)); Text(platform.title).font(.system(size: 11)) }
                                    .frame(width: unit * CGFloat(span) + CGFloat(span - 1) * 8, height: 32)
                                    .background(model.selectedPlatforms.contains(platform) ? InkStyle.selected : .clear)
                                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(model.selectedPlatforms.contains(platform) ? Color(red: 0.765, green: 0.8, blue: 0.729) : Color.gray.opacity(0.15), lineWidth: 1))
                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }.frame(height: gridHeight)
    }
    private func rows(unit: CGFloat) -> [[(PlatformID, Int)]] {
        var result: [[(PlatformID, Int)]] = [[]]; var used = 0
        for platform in PlatformID.allCases.filter({ $0.isAvailable }) {
            let text = (platform.title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width
            let span = min(3, max(1, Int(ceil((text + 17 + 4 + 8 + 8) / (unit + 8)))))
            if used + span > 6 { result.append([]); used = 0 }
            result[result.count - 1].append((platform, span)); used += span
        }
        return result
    }
    private var gridHeight: CGFloat { CGFloat(rows(unit: (384 - 40) / 6).count * 40 - 8) }
}

private struct PasteEditor: NSViewRepresentable {
    @Binding var text: String
    let enabled: Bool
    let onImages: (Data) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let editor = ImagePasteTextView(); editor.delegate = context.coordinator; editor.isRichText = false
        editor.font = .systemFont(ofSize: 13); editor.drawsBackground = false
        editor.textContainerInset = NSSize(width: 0, height: 5)
        editor.textContainer?.lineFragmentPadding = 0
        editor.isVerticallyResizable = true; editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? ImagePasteTextView else { return }
        if editor.string != text { editor.string = text }
        editor.isEditable = enabled; editor.onImages = onImages
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PasteEditor
        init(_ parent: PasteEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) { if let view = notification.object as? NSTextView { parent.text = view.string } }
    }
}
private final class ImagePasteTextView: NSTextView {
    var onImages: ((Data) -> Void)?
    override func paste(_ sender: Any?) {
        guard isEditable else { return }
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) { onImages?(data); if pasteboard.string(forType: .string) == nil { return } }
        super.paste(sender)
    }
}
