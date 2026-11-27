import Foundation
import Observation

@MainActor @Observable
public final class LayoutController {
    public private(set) var isGenerating = false
    public private(set) var message: String?
    @ObservationIgnored private var task: Task<Void, Never>?

    public init() {}

    public func format(for model: DispatchModel) {
        guard !isGenerating, model.overallPhase == .pending,
              !model.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let body = model.markdown
        isGenerating = true
        message = nil
        task = Task { @MainActor in
            defer {
                if !Task.isCancelled {
                    task = nil
                    isGenerating = false
                }
            }
            do {
                let formatted = try await LayoutService.format(body)
                guard !Task.isCancelled, model.markdown == body, model.overallPhase == .pending else { return }
                if formatted == body {
                    message = "正文无需调整"
                } else {
                    model.markdown = formatted
                }
            } catch {
                guard !Task.isCancelled else { return }
                message = error.localizedDescription
            }
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
        isGenerating = false
        message = nil
    }
}
