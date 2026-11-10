import AppKit
import SwiftUI
import Observation
import PublishKit

/// Main-window presentation only; task state stays in DispatchModel.
@MainActor @Observable
final class TaskPresentation {
    var bodyFocusRequest: UUID?
    private var hiddenTask: UUID?

    func claimHide(for model: DispatchModel) -> Bool {
        guard model.overallPhase == .preparing, model.currentPlatform != nil,
              let id = model.taskID, hiddenTask != id else { return false }
        hiddenTask = id
        return true
    }
}

struct TaskWindowPresentation: ViewModifier {
    let model: DispatchModel
    let presentation: TaskPresentation
    var dismiss: () -> Void

    func body(content: Content) -> some View {
        content.onChange(of: model.currentPlatform) { _, _ in
            guard presentation.claimHide(for: model) else { return }
            dismiss()
        }
    }
}

struct WindowReader: NSViewRepresentable {
    let receive: (NSWindow) -> Void
    func makeNSView(context: Context) -> Reader { Reader(receive: receive) }
    func updateNSView(_ view: Reader, context: Context) { view.receive = receive }
    final class Reader: NSView {
        var receive: (NSWindow) -> Void
        init(receive: @escaping (NSWindow) -> Void) { self.receive = receive; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { DispatchQueue.main.async { self.receive(window) } }
        }
    }
}

/// Menu-bar copy belongs to presentation; adapter event details never enter the label.
@MainActor
struct MenuBarStatus {
    let model: DispatchModel
    var isRunning: Bool { model.overallPhase == .preparing }
    var needsAttention: Bool {
        !isRunning && model.overallPhase != .pending && model.overallPhase != .awaitingConfirm
            && model.overallPhase != .cancelled
    }
    var message: String {
        switch model.overallPhase {
        case .pending: return ""
        case .preparing:
            return model.currentPlatform.map { "正在填写：\($0.title)" } ?? "正在准备"
        case .needLogin: return "等待登录：" + model.waitingLoginPlatforms.map(\.title).joined(separator: "、")
        case .awaitingConfirm: return "已填好，请确认"
        case .cancelled: return "已停止"
        default:
            let unfinished = model.taskPlatforms.filter {
                model.platformPhase[$0] != .awaitingConfirm && model.platformPhase[$0] != .cancelled
            }
            return unfinished.isEmpty ? "需要处理" : "需要处理：" + unfinished.map(\.title).joined(separator: "、")
        }
    }
    var title: String { message.isEmpty ? "墨" : "墨  " + message }
}
