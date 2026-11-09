# Inkpost architecture

- Product content is plain text, supporting line breaks and emoji. Preserve whitespace and characters exactly. Do not render Markdown, generate HTML, use rich-text formatting, or add content processing features. Local fixtures use plain-text controls as well.

- Inkpost is a foreground macOS application, not a background project or service. It differs from Echo; do not carry over Echo's background-process assumptions. Menu-bar presence is a UI mode and does not change this foreground application positioning.
- Use SwiftUI-adapted MVC with independent services and channel adapters. MVC defines presentation/state/coordination responsibilities; the adapter pattern isolates channel implementations within services. Keep the existing macOS 14+, Swift Package Manager stack and reuse existing implementations.
- `Sources/PublishFlow/Views/`: all UI, including pages, components, layout, styles, presentation labels, dialogs, and file pickers. Views observe `DispatchModel` and send actions to `DispatchController`. No direct browser or storage calls.
- `Sources/PublishFlow/PublishFlowApp.swift`: composition root; assemble dependencies and scenes only.
- `Sources/PublishKit/DispatchModel.swift`, `Models.swift`: observable state, domain data and platform rules. No SwiftUI/AppKit dependencies. Use `TargetPhase` for task phases instead of introducing parallel UI phase enums.
- `Sources/PublishKit/Controllers/`: coordinate dispatch, recovery, cancellation and reset; update model state through services. No UI controls, dialogs, browser scripts, HTTP or file I/O implementations.
- `Sources/PublishKit/Services/`: configuration and external execution. Reuse EgoBridge, EgoLiteEngine and PostStore. All channel workflows are deterministic; do not add model clients, API keys, model configuration or model-driven tool execution.
- Production dispatch passes a structured `ChannelRequest` to `DispatchServicing.execute`; never parse content or file paths from a goal prompt. Inject `DispatchServicing` to verify coordination without a browser or API key.
- The main dispatch flow MUST pass the complete `ChannelRequest` to every selected channel adapter: title, full body, HTML and the complete image/asset list. Preserve all supplied fields, including fields a channel does not use; never omit, clear, truncate or merge them based on the destination channel. User-omitted fields remain empty rather than being fabricated.
- Each channel adapter alone decides which supplied fields to use, ignore or transform for its platform, and owns the corresponding channel-specific verification. A channel ignoring a field does not authorize the main dispatch flow to remove it. Keep channel rules and channel-specific instructions out of the controller and main dispatch algorithm.
- `Services/Channels/` contains independent `ChannelAdapter` implementations registered through a task-scoped `ChannelRegistry`. Adapters own channel rules, input validation, platform instructions, execution steps, verification and channel recovery state. The dispatch service owns adapter invocation, task/session management, Space/Page allocation, command and snapshot validation, recovery coordination and common error conversion; it must not implement channel-specific steps.
- `ChannelContract.swift` defines fixed commands (`prepare`, `resumeAfterUser`), stage/event codes, terminal outcomes (`readyForReview`, `waitingForUser`, `failed`) and structured failures (code, stage, detail, recovery, diagnostic ID). Branch on codes/recovery only, never presentation text or model prose. UI labels belong in Views.
- Public-layer validation covers request structure, asset validity, task identity and command legality. Channel requirements belong to adapters: whether a title is mandatory, whether image-only content is accepted, supported body formats, channel image limits. The main flow may read adapter-declared capabilities to show guidance, but must not infer that `usesTitle` means a title is mandatory or impose a nonempty-body rule on every adapter; the product editor independently requires non-whitespace body and at least one channel. An adapter validates its own requirements before browser writes and returns a structured outcome when they are unmet. Do not use `PlatformRules` to centralize channel policies.
- A channel-specific validation, login or execution failure must not prevent other selected channels from being processed. Preserve the complete request and the failed channel's outcome for user action; task-wide cancellation or a shared task failure may stop the task.
- Adapters verify their complete channel-specific content transformation before returning `readyForReview`; the coordinator must not independently call a second verification API. A channel may ignore or transform a field according to its documented rules, but must not silently truncate content or discard excess images to report success.
- Every invocation carries task/platform/attempt identity. Reject stale events and results, duplicate prepare and changed-snapshot resume. Recovery reuses the original request, adapter and Page; new tasks use fresh sessions.
- Propagate `CancellationError` through adapters and the browser process executor; stop later tools/channels and retain content. A browser operation may have completed before cancellation; do not equate cancellation with rollback. Unknown write results require user inspection, never blind automatic retry.
- Native text paste and PNG paste share an exclusive clipboard lease. Text paste delegates clipboard handling to ego Lite; app-owned PNG writes restore only while the app still owns the change count. Preserve newer user copies.
- Keep architecture refactoring separate from content truncation, publishing permissions, persistence integration and new platform work. Do not claim prompt-only restrictions are enforceable security boundaries.
- Verify with `swift build`, `swift test`, and the fixture smoke flow when ego Lite is available. Do not publish to real platforms during verification.

# HTML prototype requirements

- Organize HTML prototypes vertically into three sections in this order:
  1. Top: a working visual preview, including animations and operable interactions, for the user to experience the design.
  2. Middle: requirements, features, capabilities, and states, explaining behavior and details. Clearly distinguish implemented, simulated, and planned capabilities.
  3. Bottom: design specifications and workflow explanations for developer reference.
- Keep explanatory and developer-reference sections outside the simulated product UI. Keep all three sections consistent when updating the prototype.

## Compact mode implementation

- The native NSStatusItem/NSPopover compact interface and the full workspace share one DispatchController/DispatchModel. NativeMenuBar owns menu-bar copy and fixed-size image-frame animation; animation ticks must not write title or item length. AppKit editor, picker, previews and lifecycle presentation remain in Views.
- Product workflow ends at awaitingConfirm (已填好); no product UI for published or receipt tracking. On successful workspace handoff, archive the content, images and Space identity in session history, then reset the editor while retaining channel selection. Failed handoffs and incomplete tasks must retain content. Internal fixture CLI may retain receipt checks.
- PNG encoding belongs exclusively to AssetService during task preparation, before any adapter/browser execution. DispatchService retains one complete prepared batch per task and passes its source-to-PNG mapping through ChannelExecutionContext while preserving the original ChannelRequest. Adapters upload only those PNG files; adapter-side or clipboard-side format conversion, repair, and fallback to originals are forbidden. Resume reuses the same batch; release it only after no invocation can use it. Reject unsupported animated/multiframe assets explicitly, never silently flatten them.
- Assets use AssetService for validation and byte-based SHA-256 deduplication. The editor's current six-image selection limit is a product-level constraint, independent of each channel's supported image count. Pass every selected image to each selected adapter; the adapter reports any channel-specific excess rather than silently selecting a subset. Temporary assets are not durable drafts.
- DispatchService owns one Space per task and explicitly labeled Pages per channel. Handoff and user-confirmed resume preserve context.
- Inspect is read-only; evaluate remains internal for trusted channel implementations and fixture/tools. Do not claim browser writes are an enforceable no-publish sandbox.
- Tests use built-in Swift Testing. CLT-only hosts may need explicit framework paths and disabled cross-import overlays; see README.

## Build and run workflow

- When building and running the app, use the project's configured formal code-signing identity. Do not use ad-hoc signing or silently fall back to unsigned builds. If the identity is missing or ambiguous, report the blocker and resolve the signing configuration before launching.
- After the new build succeeds and its signature is verified, automatically stop the previous Inkpost app process and launch the newly built app. Target only this application's process; do not stop unrelated processes.
- If building or signing fails, keep the existing app running and report the failure. Verify that the new app launches successfully before reporting completion.

## Issue naming

- 当用户说“为 #xx 创建分支对话”时，在当前项目内创建继承当前上下文的分支对话。标题格式为 `MMDD｜类型｜#序号 具体事项`，例如 `1107｜业务｜#10 修复标题填写`；日期使用 Asia/Shanghai 的创建日期，类型沿用对应 Issue 的模型／业务／视图分类，序号使用实际 Issue 编号。

- Present issues as `#序号 「模型/业务/视图」具体事项`, choosing one category according to the primary scope: `模型` for domain data, state and rules; `业务` for workflow, coordination and execution; `视图` for UI, layout and interactions.
- The title itself MUST include the literal `#` and the actual GitHub-assigned issue number, for example `#6 「视图」分发时自动隐藏窗口并显示菜单栏进度`. GitHub's separate number display does not satisfy this requirement. Never predict the number: create the issue, obtain its assigned number, then update its title to the complete format. When renaming, replace an existing numeric prefix rather than duplicating it.

## Channel maintenance and acceptance

- Add a channel by implementing `ChannelAdapter`, registering it in `ChannelRegistry`, and supplying platform identity/display metadata as needed. The main dispatch algorithm must remain channel-independent; do not add channel-name branches or channel-specific hints there. Presentation labels stay in Views and use adapter outcomes/capabilities rather than implementing channel rules.
- Keep channel-specific rules, verified interaction steps and known pitfalls beside the adapter in its maintenance document. When changing a channel, read and update that document together with the implementation; do not duplicate its detailed workflow in this root file. For Zhihu, read [Zhihu adapter maintenance](Sources/PublishKit/Services/Channels/ZhihuChannelAdapter.md).
- A channel's minimum acceptance coverage includes complete request delivery (including unused fields), channel-specific input validation, verified success, login/user-action waiting, structured failure and recovery classification, unchanged-snapshot resume, cancellation and rejection of stale events/results. Reuse common contract tests where possible; verify channel-specific behavior through the real adapter, not only a fake coordinator service. Browser smoke tests must stop before publication on real platforms.

## Implementation alignment

- The editor validates only product input (non-whitespace body and selected channels); DispatchService preserves the complete request and prepares task PNGs. Channel validation runs within each adapter before browser writes; a channel failure does not stop others.

## Browser workflow reliability

- The following browser rules apply to browser-based adapter implementations and their shared browser tools, not to the main dispatch algorithm. Follow the installed ego-browser skill and its current `ego-browser skill` guide. The skill is an operating contract; application code must explicitly implement that contract rather than assume skill installation controls runtime behavior.
- For a new or ambiguous platform flow, start with the user's explicit interaction guidance, verify it in the real browser, then encode the proven steps as a deterministic platform workflow. Reuse verified workflows without asking the user to guide each run.
- DOM/semantic targeting and ego Lite operations are complementary: observe a snapshot, identify a unique element by semantic locator or verified selector, perform the documented click/fill/keyboard operation, then verify the result. Snapshot refs are transient and must not be hardcoded across page changes or runs.
- Prefer website-native interactions over JavaScript that mutates DOM or editor internals. Read-only DOM inspection is appropriate for diagnosis and verification. Use coordinates only when usable semantic targeting is unavailable; do not guess selectors or navigate to unrelated creation modes after repeated failures.
- For clipboard images, prefer focusing the intended editor and sending `Meta+V` through ego Lite while the image is already on the system clipboard. `keyboard.paste(text/html)` is a different operation and does not supply image clipboard data. Use system-level key automation only if the documented ego Lite path is demonstrated insufficient.
- Verify meaningful postconditions before advancing: editor expanded, text present, image attachment uploaded. A dispatched action is not proof of success. Count actual attachments rather than raw `img` nodes; previews can live outside the text editor and contain duplicate image nodes.
- On an unexpected page or missing capability, preserve content, report the failing step and concrete error, and diagnose before changing the workflow. Log navigation destinations and tool errors without credentials or sensitive clipboard contents. Keep final publication under user control.

- Zhihu verifies logical Draft editor blocks joined by line breaks, preserving spaces and empty paragraphs; visual innerText adds extra newlines and must not drive content equality. Its task-scoped image checkpoints retain remote origin/path identities in order (without signed query strings); changed attachments or uncertain paste results require inspection. Title requirements are independent from article classification. Never invent platform length limits; honor exposed constraints and verify actual title acceptance.

知乎输入约束：标题可空，有则填写，少于 45 字（最多 44）；正文必填，包含换行和 emoji少于 1900 字（最多 1899）；图片可空。按 Swift String.count 的用户可见字符计数，中文一个字计一个字符；超限明确报错，不截断、不生成标题。

## X channel

- X uses a deterministic compose adapter without LLM configuration. Read [X adapter maintenance](Sources/PublishKit/Services/Channels/XChannelAdapter.md) before changing it. Optional title is prepended to the first line; composed plain text is limited to 1899 user-visible characters by product decision, with at most four pasted images. Verify actual editor acceptance and stop before Post.
- Dispatch preserves raw title, body, explicit HTML and ordered source assets in ChannelRequest. Dispatch does not generate HTML. Task-prepared PNG mappings stay separate from the original request.

## Deterministic channel execution

- LLM clients, tool-use loops and model configuration have been removed. Dispatch contracts carry content and execution identity only.
- Zhihu, Jike, X and the local fixture use deterministic workflows. Read `Sources/PublishKit/Services/Channels/JikeChannelAdapter.md` before changing Jike; keep its inline composer, exact text verification and ordered attachment recovery within its adapter.

## Weibo channel

- Weibo opens the Quick Publish panel from the homepage “发微博” button, waits for automatic focus, and uses panel-scoped native body/PNG paste and ordered remote attachment checkpoints. Read [Weibo adapter maintenance](Sources/PublishKit/Services/Channels/WeiboChannelAdapter.md) before changing it. A nonempty title is prepended to the body with one newline, preserving both fields exactly; an empty title adds no newline. Explicit HTML is unused and the original request remains intact. Preserve existing page drafts; do not enter long-article mode or click Send.

## Juejin pins channel

- Read [Juejin adapter maintenance](Sources/PublishKit/Services/Channels/JuejinChannelAdapter.md) before changing it. Ordinary pins only; title is optionally prepended with one newline, composed text at most 1000 UTF-16 units. First filling clears old body/attachments as authorized; resume must never clear again. Preserve raw editor input; the website itself trims edge whitespace on submission. Attachments are staged locally and uploaded only by the user’s final Publish action; verify all staged images without claiming remote upload.
