# Inkpost architecture

- Inkpost is a foreground macOS application, not a background project or service. It differs from Echo; do not carry over Echo's background-process assumptions. Menu-bar presence is a UI mode and does not change this foreground application positioning.
- Use SwiftUI-adapted MVC with independent services. Keep the existing macOS 14+, Swift Package Manager stack and reuse existing implementations.
- `Sources/PublishFlow/Views/`: all UI, including pages, components, layout, styles, presentation labels, dialogs, and file pickers. Views observe `DispatchModel` and send actions to `DispatchController`. No direct LLM, browser, or storage calls.
- `Sources/PublishFlow/PublishFlowApp.swift`: composition root; assemble dependencies and scenes only.
- `Sources/PublishKit/DispatchModel.swift`, `Models.swift`, `PlatformRules.swift`: observable state, domain data and platform rules. No SwiftUI/AppKit dependencies. Use `TargetPhase` for task phases instead of introducing parallel UI phase enums.
- `Sources/PublishKit/Controllers/`: coordinate dispatch, reset and receipt reads; update model state through services. No UI controls, dialogs, browser scripts, HTTP or file I/O implementations.
- `Sources/PublishKit/Services/`: configuration and external execution. Existing AgentLoop, EgoBridge, EgoLiteEngine and PostStore remain reusable service implementations.
- GUI and CLI share the `AgentDispatchService.run` execution entry point. Inject `DispatchServicing` to verify coordination without a browser or API key.
- Keep architecture refactoring separate from content truncation, publishing permissions, persistence integration and new platform work. Do not claim prompt-only restrictions are enforceable security boundaries.
- Verify with `swift build`, `swift test`, and the fixture smoke flow when ego Lite is available. Do not publish to real platforms during verification.

# HTML prototype requirements

- Organize HTML prototypes vertically into three sections in this order:
  1. Top: a working visual preview, including animations and operable interactions, for the user to experience the design.
  2. Middle: requirements, features, capabilities, and states, explaining behavior and details. Clearly distinguish implemented, simulated, and planned capabilities.
  3. Bottom: design specifications and workflow explanations for developer reference.
- Keep explanatory and developer-reference sections outside the simulated product UI. Keep all three sections consistent when updating the prototype.

## Compact mode implementation

- MenuBarExtra and the full workspace share one DispatchController/DispatchModel. AppKit editor, picker, previews and lifecycle presentation remain in Views.
- Product workflow ends at awaitingConfirm (已填好); no product UI for published or receipt tracking. Internal fixture CLI may retain receipt checks.
- Assets use AssetService for validation, byte-based SHA-256 deduplication and six-image limits. Temporary assets are not durable drafts.
- AgentDispatchService owns one Space per task and explicitly labeled Pages per channel. Handoff and user-confirmed resume preserve context.
- Agent-visible inspect is fixed read-only; arbitrary evaluate remains internal for fixture/tools. Do not claim browser writes are an enforceable no-publish sandbox.
- Tests use built-in Swift Testing. CLT-only hosts may need explicit framework paths and disabled cross-import overlays; see README.

## Build and run workflow

- When building and running the app, use the project's configured formal code-signing identity. Do not use ad-hoc signing or silently fall back to unsigned builds. If the identity is missing or ambiguous, report the blocker and resolve the signing configuration before launching.
- After the new build succeeds and its signature is verified, automatically stop the previous Inkpost app process and launch the newly built app. Target only this application's process; do not stop unrelated processes.
- If building or signing fails, keep the existing app running and report the failure. Verify that the new app launches successfully before reporting completion.

## Issue naming

- Present issues as `#序号 「模型/业务/视图」具体事项`, choosing one category according to the primary scope: `模型` for domain data, state and rules; `业务` for workflow, coordination and execution; `视图` for UI, layout and interactions.
- The title itself MUST include the literal `#` and the actual GitHub-assigned issue number, for example `#6 「视图」分发时自动隐藏窗口并显示菜单栏进度`. GitHub's separate number display does not satisfy this requirement. Never predict the number: create the issue, obtain its assigned number, then update its title to the complete format. When renaming, replace an existing numeric prefix rather than duplicating it.
