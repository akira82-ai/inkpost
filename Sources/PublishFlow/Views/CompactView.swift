import SwiftUI
import AppKit
import PublishKit

struct CompactView: View {
    @Bindable var model: DispatchModel
    let controller: DispatchController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        composer
        .frame(width: min(420, (NSScreen.main?.visibleFrame.width ?? 1440) - 24))
        .fixedSize(horizontal: false, vertical: true)
        .background(InkStyle.paper)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.75)))
        .foregroundStyle(InkStyle.ink).preferredColorScheme(.light)
        .modifier(NoticeOverlay(model: model))
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }
    private var composer: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                InkBrand()
                Spacer()
                QuietIcon(symbol: "arrow.up.right.square", label: "打开完整界面", size: 30) {
                    openWindow(id: "workspace")
                    NSApp.activate(ignoringOtherApps: true)
                    dismiss()
                }
            }.padding(.top, 16).padding(.horizontal, 18).padding(.bottom, 10)
            VStack(spacing: 0) {
                ComposerFields(model: model, onImages: controller.pasteImage, onFiles: controller.addAssets)
                AttachmentStrip(model: model, controller: controller)
                HStack {
                    Text("投递到")
                    Spacer()
                    Text("\(model.selectedPlatforms.count) 个渠道")
                }.font(InkStyle.font(10)).foregroundStyle(InkStyle.muted).padding(.top, 14).padding(.bottom, 8)
                ChannelGrid(model: model, controller: controller)
                if model.overallPhase != .pending {
                    DispatchStatus(model: model, controller: controller).padding(.top, 14)
                }
                if let error = model.errorMessage {
                    Text(error).font(InkStyle.font(11)).foregroundStyle(InkStyle.warning).padding(.top, 8)
                }
            }.padding(.horizontal, 18).padding(.bottom, 13)
            Rectangle().fill(InkStyle.line).frame(height: 1)
            VStack(spacing: 9) {
                DispatchAction(model: model, controller: controller)
                Text("最终发布由你确认").font(InkStyle.font(10)).foregroundStyle(Color(hex: 0x929889))
                if model.overallPhase == .awaitingConfirm {
                    Button("开始新一份", action: controller.newDraft).buttonStyle(.plain).font(InkStyle.font(10)).foregroundStyle(InkStyle.muted)
                } else if model.overallPhase == .failed {
                    Button("修改未完成渠道的内容", action: controller.editUnfinishedChannels).buttonStyle(.plain).font(InkStyle.font(10)).foregroundStyle(InkStyle.muted)
                }
            }.padding(.top, 11).padding(.horizontal, 18).padding(.bottom, 15)
        }.fixedSize(horizontal: false, vertical: true)
    }
}
