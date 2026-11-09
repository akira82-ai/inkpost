import SwiftUI
import AppKit
import PublishKit

struct CompactView: View {
    @Bindable var model: DispatchModel
    let controller: DispatchController
    let presentation: TaskPresentation
    var dismissCompact: (() -> Void)? = nil
    @State private var showExecutionLog = false
    @State private var mainWindow: NSWindow?
    var body: some View {
        composer
        .frame(width: min(420, (NSScreen.main?.visibleFrame.width ?? 1440) - 24))
        .fixedSize(horizontal: false, vertical: true)
        .background(InkStyle.paper)
        .background(WindowReader { mainWindow = $0 })
        .foregroundStyle(InkStyle.ink).preferredColorScheme(.light)
        .modifier(NoticeOverlay(model: model))
        .modifier(TaskWindowPresentation(model: model, presentation: presentation, dismiss: { closeCompact() }))
    }
    private func closeCompact() {
        if let dismissCompact { dismissCompact() }
        else { mainWindow?.orderOut(nil); presentation.compactVisible = false }
    }
    private var composer: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                ComposerFields(model: model, bodyFocusRequest: presentation.compactFocusRequest, onImages: controller.pasteImage, onFiles: controller.addAssets)
                AttachmentStrip(model: model, controller: controller)
                HStack {
                    Text("投递到")
                    Spacer()
                    Text("\(model.selectedPlatforms.count) 个渠道")
                }.font(InkStyle.font(10)).foregroundStyle(InkStyle.muted).padding(.top, 14).padding(.bottom, 8)
                ChannelGrid(model: model, controller: controller)

            }.padding(.top, 12).padding(.horizontal, 18).padding(.bottom, 13)
            Rectangle().fill(InkStyle.line).frame(height: 1)
            VStack(spacing: 9) {
                DispatchAction(model: model, controller: controller)
                DispatchStatus(model: model)
                if model.overallPhase == .preparing {
                    Button("停止填写", action: controller.cancel).buttonStyle(.plain).font(InkStyle.font(11))
                }
                ForEach(model.taskPlatforms) { platform in
                    if let outcome = model.platformOutcomes[platform], let failure = outcome.failure {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(platform.title)：\(model.platformMessages[platform] ?? failure.detail)")
                                .textSelection(.enabled)
                            if outcome.canResume {
                                Button(failure.recovery.actionTitle) { controller.resume(platform) }
                                    .disabled(model.overallPhase == .preparing)
                            }
                        }.font(InkStyle.font(11)).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if [.failed, .cancelled].contains(model.overallPhase) {
                    Button("修改未完成渠道的内容", action: controller.editUnfinishedChannels).buttonStyle(.plain).font(InkStyle.font(11))
                }
                if !model.eventLog.isEmpty {
                    DisclosureGroup("执行日志（\(model.eventLog.count) 条）", isExpanded: $showExecutionLog) {
                        ScrollView {
                            Text(model.eventLog.joined(separator: "\n")).textSelection(.enabled)
                                .font(.system(size: 10, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(height: 120)
                    }.font(InkStyle.font(11))
                }
            }.padding(.top, 11).padding(.horizontal, 18).padding(.bottom, 15)
        }.fixedSize(horizontal: false, vertical: true)
    }
}
