# Inkpost architecture

- Use SwiftUI-adapted MVC with independent services. Keep the existing macOS 14+, Swift Package Manager stack and reuse existing implementations.
- `Sources/PublishFlow/Views/`: all UI, including pages, components, layout, styles, presentation labels, dialogs, and file pickers. Views observe `DispatchModel` and send actions to `DispatchController`. No direct LLM, browser, or storage calls.
- `Sources/PublishFlow/PublishFlowApp.swift`: composition root; assemble dependencies and scenes only.
- `Sources/PublishKit/DispatchModel.swift`, `Models.swift`, `PlatformRules.swift`: observable state, domain data and platform rules. No SwiftUI/AppKit dependencies. Use `TargetPhase` for task phases instead of introducing parallel UI phase enums.
- `Sources/PublishKit/Controllers/`: coordinate dispatch, reset and receipt reads; update model state through services. No UI controls, dialogs, browser scripts, HTTP or file I/O implementations.
- `Sources/PublishKit/Services/`: configuration and external execution. Existing AgentLoop, EgoBridge, EgoLiteEngine and PostStore remain reusable service implementations.
- GUI and CLI share the `AgentDispatchService.run` execution entry point. Inject `DispatchServicing` to verify coordination without a browser or API key.
- Keep architecture refactoring separate from content truncation, publishing permissions, persistence integration and new platform work. Do not claim prompt-only restrictions are enforceable security boundaries.
- Verify with `swift build`, `swift test`, and the fixture smoke flow when ego Lite is available. Do not publish to real platforms during verification.
