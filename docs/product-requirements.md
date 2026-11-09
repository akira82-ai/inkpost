# Inkpost 产品需求与验收细节

本文集中记录产品行为及其实现验收要求，不作为项目协作规范。用户确认的新需求更新本文；历史实现或旧文档不能限制新需求。

## 状态说明

- 本次确认的窗口需求：常驻菜单栏、Dock 不显示图标、点击菜单栏在当前桌面唤醒同一发布窗口且不切换桌面；唤醒时置前，切换其他 App 后正常排序。
- #45 已完成代码适配：打包声明 `LSUIElement`，启动使用 `.accessory`；各入口统一唤醒场景主窗口，使用 `.moveToActiveSpace` 和普通窗口层级。构建、自动测试与原生现场验证分别记录在开发参考中，不以配置值代替跨桌面验收。
- 下文其余条目从原 AGENTS.md 迁入，保留已有需求与验收细节；迁移不表示本轮重新验证了实现。

## 内容、执行与数据要求

- Product content is plain text, supporting line breaks and emoji. Preserve whitespace and characters exactly. Do not render Markdown, generate HTML, use rich-text formatting, or add content processing features. Local fixtures use plain-text controls as well.

- Inkpost is a menu-bar macOS application with no Dock icon. Clicking the menu-bar icon shows and activates the same publishing window on the user's current desktop without switching desktops. The publishing window uses normal window ordering: bring it forward on explicit invocation, then let other apps cover it normally. Do not use permanent floating levels or repeated activation to keep it in front.
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

## Main window implementation

- Inkpost has one ordinary NSWindow at normal level using the former compact layout. No compact/full publishing mode or second editor. The former workspace is Settings only; do not add configuration capabilities during this migration.
- Use the native titlebar with title 墨驿, visible standard close/minimize buttons and a disabled gray zoom button; no resizing or fullscreen. Close and minimize both hide the main window without quitting, cancelling, or minimizing to Dock. The right gear opens Settings.
- Clicking the menu-bar icon shows or brings forward the same main window, including when it is covered by another app or belongs to another desktop; visibility alone must never make a click hide it. Explicit opening brings the window to the current desktop without switching desktops, activates once and focuses the body. Switching apps leaves it visible behind other apps, without raising Settings. Do not provide a Dock entry or depend on Dock reopen for access.
- Hide automatically once only after valid Start Filling begins execution. Progress, completion, failure, cancellation, login waiting, focus loss and Escape must not change visibility.
- Main window and Settings share one DispatchController/DispatchModel. Task operations, recovery, errors and logs belong in the main window. NativeMenuBar owns status copy and fixed-size image animation; animation ticks never write title or item length. Window lifecycle remains in Views.

- Product workflow ends at awaitingConfirm (已填好); no product UI for published or receipt tracking. On successful workspace handoff, archive the content, images and Space identity in session history, then reset the editor while retaining channel selection. Failed handoffs and incomplete tasks must retain content. Internal fixture CLI may retain receipt checks.
- PNG encoding belongs exclusively to AssetService during task preparation, before any adapter/browser execution. DispatchService retains one complete prepared batch per task and passes its source-to-PNG mapping through ChannelExecutionContext while preserving the original ChannelRequest. Adapters upload only those PNG files; adapter-side or clipboard-side format conversion, repair, and fallback to originals are forbidden. Resume reuses the same batch; release it only after no invocation can use it. Reject unsupported animated/multiframe assets explicitly, never silently flatten them.
- Assets use AssetService for validation and byte-based SHA-256 deduplication. The editor's current six-image selection limit is a product-level constraint, independent of each channel's supported image count. Pass every selected image to each selected adapter; the adapter reports any channel-specific excess rather than silently selecting a subset. Temporary assets are not durable drafts.
- DispatchService owns one Space per task and explicitly labeled Pages per channel. Handoff and user-confirmed resume preserve context.
- Inspect is read-only; evaluate remains internal for trusted channel implementations and fixture/tools. Do not claim browser writes are an enforceable no-publish sandbox.

## 渠道验收

- A channel's minimum acceptance coverage includes complete request delivery (including unused fields), channel-specific input validation, verified success, login/user-action waiting, structured failure and recovery classification, unchanged-snapshot resume, cancellation and rejection of stale events/results. Reuse common contract tests where possible; verify channel-specific behavior through the real adapter, not only a fake coordinator service. Browser smoke tests must stop before publication on real platforms.

## Implementation alignment

- The editor validates only product input (non-whitespace body and selected channels); DispatchService preserves the complete request and prepares task PNGs. Channel validation runs within each adapter before browser writes; a channel failure does not stop others.

## 渠道行为与约束

- Zhihu verifies logical Draft editor blocks joined by line breaks, preserving spaces and empty paragraphs; visual innerText adds extra newlines and must not drive content equality. Its task-scoped image checkpoints retain remote origin/path identities in order (without signed query strings); changed attachments or uncertain paste results require inspection. Title requirements are independent from article classification. Never invent platform length limits; honor exposed constraints and verify actual title acceptance.

知乎输入约束：标题可空，有则填写，少于 45 字（最多 44）；正文必填，包含换行和 emoji少于 1900 字（最多 1899）；图片可空。按 Swift String.count 的用户可见字符计数，中文一个字计一个字符；超限明确报错，不截断、不生成标题。

## X channel

- X uses a deterministic compose adapter without LLM configuration. Read [X adapter maintenance](../Sources/PublishKit/Services/Channels/XChannelAdapter.md) before changing it. Optional title is prepended to the first line; composed plain text is limited to 1899 user-visible characters by product decision, with at most four pasted images. Verify actual editor acceptance and stop before Post.
- Dispatch preserves raw title, body, explicit HTML and ordered source assets in ChannelRequest. Dispatch does not generate HTML. Task-prepared PNG mappings stay separate from the original request.

## Deterministic channel execution

- LLM clients, tool-use loops and model configuration have been removed. Dispatch contracts carry content and execution identity only.
- Zhihu, Jike, X and the local fixture use deterministic workflows. Read `Sources/PublishKit/Services/Channels/JikeChannelAdapter.md` before changing Jike; keep its inline composer, exact text verification and ordered attachment recovery within its adapter.

## Weibo channel

- Weibo opens the Quick Publish panel from the homepage “发微博” button, waits for automatic focus, and uses panel-scoped native body/PNG paste and ordered remote attachment checkpoints. Read [Weibo adapter maintenance](../Sources/PublishKit/Services/Channels/WeiboChannelAdapter.md) before changing it. A nonempty title is prepended to the body with one newline, preserving both fields exactly; an empty title adds no newline. Explicit HTML is unused and the original request remains intact. Preserve existing page drafts; do not enter long-article mode or click Send.

## Juejin pins channel

- Read [Juejin adapter maintenance](../Sources/PublishKit/Services/Channels/JuejinChannelAdapter.md) before changing it. Ordinary pins only; title is optionally prepended with one newline, composed text at most 1000 UTF-16 units. First filling clears old body/attachments as authorized; resume must never clear again. Preserve raw editor input; the website itself trims edge whitespace on submission. Attachments are staged locally and uploaded only by the user’s final Publish action; verify all staged images without claiming remote upload.
