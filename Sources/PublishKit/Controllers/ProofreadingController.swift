import Foundation
import Observation

@MainActor @Observable
public final class ProofreadingController {
    enum Field: String, Decodable { case title, body }
    struct Draft: Encodable, Equatable {
        var title: String
        var body: String

        subscript(field: Field) -> String {
            get { field == .title ? title : body }
            set { if field == .title { title = newValue } else { body = newValue } }
        }
    }
    struct ProposedEdit: Decodable {
        let field: Field
        let original: String
        let replacement: String
        let occurrence: Int
        let reason: String
    }
    public struct Suggestion: Identifiable {
        public let id = UUID()
        let edit: ProposedEdit
        var range: NSRange
        public var isTitle: Bool { edit.field == .title }
        public var original: String { edit.original }
        public var replacement: String { edit.replacement }
        public var reason: String { edit.reason }
    }

    public private(set) var suggestions: [Suggestion] = []
    public private(set) var isChecking = false
    public private(set) var message: String?
    private var draft: Draft?
    @ObservationIgnored private var task: Task<Void, Never>?

    public init() {}

    public func check(_ model: DispatchModel) {
        guard !isChecking, model.overallPhase == .pending else { return }
        let draft = current(model)
        guard !(draft.title + draft.body).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        reset()
        isChecking = true
        self.draft = draft
        task = Task {
            defer { if !Task.isCancelled { isChecking = false; task = nil } }
            do {
                let url = try Resources.url("proofread", ext: "txt", sub: "Prompts")
                let prompt = try String(contentsOf: url, encoding: .utf8)
                let input = String(decoding: try JSONEncoder().encode(draft), as: UTF8.self)
                let response = try await AIClient.shared.complete(configuration: AISettings().load(),
                    key: AISettings.readKey(), system: prompt, text: input)
                guard !Task.isCancelled, current(model) == draft, model.overallPhase == .pending else { return }
                suggestions = try Self.resolve(response, in: draft)
            } catch {
                if !Task.isCancelled { message = error.localizedDescription }
            }
        }
    }

    static func resolve(_ response: String, in draft: Draft) throws -> [Suggestion] {
        let edits = try JSONDecoder().decode([ProposedEdit].self, from: Data(response.utf8))
        var results: [Suggestion] = []
        for edit in edits.prefix(40) {
            guard !edit.original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  edit.original != edit.replacement, edit.occurrence > 0,
                  !edit.original.contains(where: \.isNewline),
                  !edit.replacement.contains(where: \.isNewline) else { continue }
            let text = draft[edit.field]
            var start = text.startIndex
            var index = 0
            while let match = text.range(of: edit.original, options: .literal, range: start..<text.endIndex) {
                index += 1
                start = match.upperBound
                guard index == edit.occurrence else { continue }
                let range = NSRange(match, in: text)
                if !results.contains(where: { $0.edit.field == edit.field && NSIntersectionRange($0.range, range).length > 0 }) {
                    results.append(Suggestion(edit: edit, range: range))
                }
                break
            }
        }
        return results.sorted {
            if $0.isTitle != $1.isTitle { return $0.isTitle }
            return $0.range.location < $1.range.location
        }
    }

    public func location(_ id: UUID, in model: DispatchModel) -> (isTitle: Bool, range: NSRange)? {
        guard draft == current(model), model.overallPhase == .pending,
              let item = suggestions.first(where: { $0.id == id }) else { return nil }
        return (item.isTitle, item.range)
    }

    public func replace(_ id: UUID, in model: DispatchModel) {
        guard location(id, in: model) != nil, var draft,
              let item = suggestions.first(where: { $0.id == id }),
              let range = Range(item.range, in: draft[item.edit.field]) else { return }
        let delta = item.replacement.utf16.count - item.range.length
        draft[item.edit.field].replaceSubrange(range, with: item.replacement)
        self.draft = draft
        ignore(id)
        for index in suggestions.indices where suggestions[index].edit.field == item.edit.field &&
            suggestions[index].range.location >= NSMaxRange(item.range) {
            suggestions[index].range.location += delta
        }
        if item.isTitle { model.title = draft.title } else { model.markdown = draft.body }
    }

    public func ignore(_ id: UUID) { suggestions.removeAll { $0.id == id } }

    public func draftChanged(_ model: DispatchModel) {
        if draft != current(model) { reset() }
    }

    public func reset() {
        task?.cancel()
        task = nil
        draft = nil
        suggestions = []
        isChecking = false
        message = nil
    }

    private func current(_ model: DispatchModel) -> Draft {
        Draft(title: model.title, body: model.markdown)
    }
}
