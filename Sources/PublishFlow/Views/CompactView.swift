import SwiftUI
import AppKit
import PublishKit

struct CompactView: View {
    @Bindable var model: DispatchModel
    let controller: DispatchController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var bodyFocusRequest: UUID?
    var body: some View {
        composer
        .frame(width: min(420, (NSScreen.main?.visibleFrame.width ?? 1440) - 24))
        .fixedSize(horizontal: false, vertical: true)
        .background(InkStyle.paper)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.75)))
        .foregroundStyle(InkStyle.ink).preferredColorScheme(.light)
        .modifier(NoticeOverlay(model: model))
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            bodyFocusRequest = UUID()
        }
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
                ComposerFields(model: model, bodyFocusRequest: bodyFocusRequest, onImages: controller.pasteImage, onFiles: controller.addAssets)
                AttachmentStrip(model: model, controller: controller)
                HStack {
                    Text("投递到")
                    Spacer()
                    Text("\(model.selectedPlatforms.count) 个渠道")
                }.font(InkStyle.font(10)).foregroundStyle(InkStyle.muted).padding(.top, 14).padding(.bottom, 8)
                ChannelGrid(model: model, controller: controller)

            }.padding(.horizontal, 18).padding(.bottom, 13)
            Rectangle().fill(InkStyle.line).frame(height: 1)
            VStack(spacing: 9) {
                DispatchAction(model: model, controller: controller)
                DispatchStatus(model: model)
            }.padding(.top, 11).padding(.horizontal, 18).padding(.bottom, 15)
        }.fixedSize(horizontal: false, vertical: true)
    }
}
