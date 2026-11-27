import Foundation
import Observation

@MainActor @Observable
public final class TopicController {
    public private(set) var isGenerating = false
    public private(set) var message: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    private var appended: String?
    private var lastChange: (previous: String?, current: String)?

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
        message = "正在生成话题…"
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
                lastChange = (previous, suffix)
                appended = suffix
                model.markdown = base + suffix
                message = nil
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                message = error.localizedDescription
            }
        }
    }

    public func canUndo(in body: String) -> Bool {
        lastChange.map { body.hasSuffix($0.current) } ?? false
    }

    public func undo(in model: DispatchModel) {
        guard !isGenerating, model.overallPhase == .pending,
              let lastChange, canUndo(in: model.markdown) else { return }
        model.markdown = String(model.markdown.dropLast(lastChange.current.count)) + (lastChange.previous ?? "")
        appended = lastChange.previous
        self.lastChange = nil
        message = nil
    }

    public func contentChanged(to body: String) {
        cancel()
        if let appended, !body.hasSuffix(appended) {
            self.appended = nil
            lastChange = nil
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
