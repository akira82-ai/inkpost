import SwiftUI
import AppKit
import PublishKit

struct CompactView: View {
    @Bindable var model: DispatchModel
    let controller: DispatchController
    let presentation: TaskPresentation
    @State private var mainWindow: NSWindow?
    var body: some View {
        composer
        .frame(width: min(420, (NSScreen.main?.visibleFrame.width ?? 1440) - 24))
        .fixedSize(horizontal: false, vertical: true)
        .background(InkStyle.paper)
        .background(WindowReader { mainWindow = $0 })
        .foregroundStyle(InkStyle.ink).preferredColorScheme(.light)
        .modifier(NoticeOverlay(model: model))
        .onChange(of: model.overallPhase) { _, phase in
            if phase == .pending { presentation.bodyFocusRequest = UUID() }
        }
        .modifier(TaskWindowPresentation(model: model, presentation: presentation, dismiss: { mainWindow?.orderOut(nil) }))
    }
    private var composer: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                ComposerFields(model: model, bodyFocusRequest: presentation.bodyFocusRequest, onImages: controller.pasteImage, onFiles: controller.addAssets)
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
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    DispatchStatus(model: model)
                    if model.overallPhase == .needLogin {
                        Rectangle().fill(InkStyle.line).frame(width: 1, height: 12)
                        Button("跳过，手工处理", action: controller.skipWaitingLogins)
                            .buttonStyle(.plain).font(InkStyle.font(11)).foregroundStyle(InkStyle.muted)
                            .disabled(model.isHandingOff || model.isSettling)
                    }
                }.frame(maxWidth: .infinity)
                if model.overallPhase == .preparing {
                    Button("停止填写", action: controller.cancel).buttonStyle(.plain).font(InkStyle.font(11))
                }
                if let message = model.navigationMessage {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(message).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        if model.canIgnoreWorkspaceError && model.hasEnded {
                            Button(action: controller.ignoreWorkspaceError) {
                                Text("我已处理，忽略").underline()
                            }.buttonStyle(.plain)
                                .fixedSize()
                                .disabled(model.isHandingOff || model.isSettling)
                                .accessibilityHint("清空本次内容并恢复初始状态，保留渠道选择")
                        }
                    }.font(InkStyle.font(10)).foregroundStyle(Color(hex: 0x8B542B))
                        .frame(maxWidth: .infinity)
                }
            }.padding(.top, 11).padding(.horizontal, 18).padding(.bottom, 15)
        }.fixedSize(horizontal: false, vertical: true)
    }
}
