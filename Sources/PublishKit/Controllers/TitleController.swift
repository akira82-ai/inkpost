import Foundation
import Observation

@MainActor @Observable
public final class TitleController {
    public private(set) var isGenerating = false
    public private(set) var message: String?
    @ObservationIgnored private var task: Task<Void, Never>?

    public init() {}

    public func generate(for model: DispatchModel) {
        guard !isGenerating, model.overallPhase == .pending, model.title.isEmpty,
              !model.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let body = model.markdown
        let platforms = model.selectedPlatforms
        let platform = platforms.count == 1 ? platforms.first?.title : nil
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
                let title = try await TitleService.generate(draft: .init(body: body, platform: platform, maxLength: nil))
                guard !Task.isCancelled, model.title.isEmpty, model.markdown == body,
                      model.selectedPlatforms == platforms, model.overallPhase == .pending else { return }
                if title.isEmpty {
                    message = "没有合适的标题"
                } else {
                    model.title = title
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
