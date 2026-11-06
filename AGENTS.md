# Inkpost architecture

- Inkpost is a foreground macOS application, not a background project or service. It differs from Echo; do not carry over Echo's background-process assumptions. Menu-bar presence is a UI mode and does not change this foreground application positioning.
- Use SwiftUI-adapted MVC with independent services. Keep the existing macOS 14+, Swift Package Manager stack and reuse existing implementations.
- `Sources/PublishFlow/Views/`: all UI, including pages, components, layout, styles, presentation labels, dialogs, and file pickers. Views observe `DispatchModel` and send actions to `DispatchController`. No direct LLM, browser, or storage calls.
- `Sources/PublishFlow/PublishFlowApp.swift`: composition root; assemble dependencies and scenes only.
- `Sources/PublishKit/DispatchModel.swift`, `Models.swift`, `PlatformRules.swift`: observable state, domain data and platform rules. No SwiftUI/AppKit dependencies. Use `TargetPhase` for task phases instead of introducing parallel UI phase enums.
- `Sources/PublishKit/Controllers/`: coordinate dispatch, reset and receipt reads; update model state through services. No UI controls, dialogs, browser scripts, HTTP or file I/O implementations.
- `Sources/PublishKit/Services/`: configuration and external execution. Existing AgentLoop, EgoBridge, EgoLiteEngine and PostStore remain reusable service implementations.
- GUI and CLI agent flows share `AgentDispatchService.run`. Production dispatch passes a structured `ChannelRequest` to `DispatchServicing.prepare`; never parse content or file paths from a goal prompt. Inject `DispatchServicing` to verify coordination without a browser or API key.
- `Services/Channels/` contains independent `ChannelAdapter` implementations registered through a task-scoped `ChannelRegistry`. Adapters own platform instructions, navigation, verification and recovery state; the dispatch service owns Space/Page allocation only. Capabilities drive title/configuration requirements and image limits without platform branches in the controller. Zhihu retains its deterministic homepage composer and sequential paste; shared clipboard ownership/restoration lives in `ImageClipboardSession`.
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
- Product workflow ends at awaitingConfirm (已填好); no product UI for published or receipt tracking. On successful workspace handoff, archive the content, images and Space identity in session history, then reset the editor while retaining channel selection. Failed handoffs and incomplete tasks must retain content. Internal fixture CLI may retain receipt checks.
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

## Zhihu channel

- Zhihu supports thoughts (想法) only, using the home-page composer at `https://www.zhihu.com/`, not column articles. Fill the complete body and images, leave the supplied title unused, and stop before the final 发想法 action. Do not assume the editor has saved a durable draft.

- Zhihu navigation is restricted to its home page and deterministically expands the thought composer by clicking 分享此刻的想法 before waiting for visible title/body controls. Do not expose arbitrary click to repair this activation step.

## Browser workflow reliability

- Follow the installed ego-browser skill and its current `ego-browser skill` guide. The skill is an operating contract; application code must explicitly implement that contract rather than assume skill installation controls runtime behavior.
- For a new or ambiguous platform flow, start with the user's explicit interaction guidance, verify it in the real browser, then encode the proven steps as a deterministic platform workflow. Reuse verified workflows without asking the user to guide each run.
- DOM/semantic targeting and ego Lite operations are complementary: observe a snapshot, identify a unique element by semantic locator or verified selector, perform the documented click/fill/keyboard operation, then verify the result. Snapshot refs are transient and must not be hardcoded across page changes or runs.
- Prefer website-native interactions over JavaScript that mutates DOM or editor internals. Read-only DOM inspection is appropriate for diagnosis and verification. Use coordinates only when usable semantic targeting is unavailable; do not guess selectors or navigate to unrelated creation modes after repeated failures.
- For clipboard images, prefer focusing the intended editor and sending `Meta+V` through ego Lite while the image is already on the system clipboard. `keyboard.paste(text/html)` is a different operation and does not supply image clipboard data. Use system-level key automation only if the documented ego Lite path is demonstrated insufficient.
- Verify meaningful postconditions before advancing: editor expanded, text present, image attachment uploaded. A dispatched action is not proof of success. Count actual attachments rather than raw `img` nodes; previews can live outside the text editor and contain duplicate image nodes.
- Zhihu uses app-managed PNG clipboard writes and ego Lite `Meta+V`, one image at a time. Wait for an HTTPS-backed loaded attachment and absence of its upload spinner; count attachment tiles, not duplicated image previews. Two-image upload, repeat-run deduplication, complete body verification and clipboard restoration were verified using generated images. Unknown previous paste results require manual inspection rather than blind retry. Restore the prior clipboard only while the app still owns its change count; preserve newer user copies. Login expiry, network failures and concurrent user clipboard changes still need live fault-injection testing.
- On an unexpected page or missing capability, preserve content, report the failing step and concrete error, and diagnose before changing the workflow. Log navigation destinations and tool errors without credentials or sensitive clipboard contents. Keep final publication under user control.

- Zhihu: never send Escape to dismiss topic suggestions: it collapses the thoughts composer even with content. Paste the complete body and tags once, then paste images sequentially, waiting for each upload. Do not add a title-field click or dismiss topic suggestions. The Escape collapse was reproduced; the flow without Escape was verified in the same failing Space.
