import Foundation
import Observation

@MainActor @Observable
public final class TopicController {
    public private(set) var isGenerating = false
    public private(set) var message: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    private var appended: String?

    public init() {}

    public func generate(for model: DispatchModel) {
        guard !isGenerating, model.overallPhase == .pending,
              !model.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let original = model.markdown
        let previous = appended.flatMap { original.hasSuffix($0) ? $0 : nil }
        let base = previous.map { String(original.dropLast($0.count)) } ?? original
        let originalTitle = model.title
        let platforms = model.selectedPlatforms
        let platform = platforms.contains(.x) ? "X" : (platforms.count == 1 ? platforms.first?.title : nil)
        let token = UUID()
        generation = token
        isGenerating = true
        message = nil
        task = Task { @MainActor in
            defer {
                if generation == token {
                    task = nil
                    isGenerating = false
                }
            }
            do {
                let tags = try await TopicService.generate(draft: .init(title: originalTitle, body: base, platform: platform))
                guard generation == token, !Task.isCancelled else { return }
                guard model.title == originalTitle, model.markdown == original,
                      model.selectedPlatforms == platforms, model.overallPhase == .pending else {
                    message = nil
                    return
                }
                guard !tags.isEmpty else {
                    message = "没有合适的话题"
                    return
                }
                let separator = base.hasSuffix("\n\n") ? "" : (base.hasSuffix("\n") ? "\n" : "\n\n")
                let suffix = separator + tags.map { "#" + $0 }.joined(separator: " ")
                appended = suffix
                model.markdown = base + suffix
                message = nil
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                message = error.localizedDescription
            }
        }
    }

    public func contentChanged(to body: String) {
        cancel()
        if let appended, !body.hasSuffix(appended) {
            self.appended = nil
        }
    }

    public func cancel() {
        guard isGenerating else { return }
        generation = UUID()
        task?.cancel()
        task = nil
        isGenerating = false
        message = nil
    }
}
