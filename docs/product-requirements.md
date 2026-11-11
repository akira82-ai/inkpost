# Inkpost 产品需求与验收细节

本文集中记录产品行为及其实现验收要求，不作为项目协作规范。用户确认的新需求更新本文；历史实现或旧文档不能限制新需求。

## 状态说明

- 本次确认的窗口需求：常驻菜单栏、Dock 不显示图标、点击菜单栏在当前桌面唤醒同一发布窗口且不切换桌面；唤醒时置前，切换其他 App 后正常排序。
- #45 已完成代码适配：打包声明 `LSUIElement`，启动使用 `.accessory`；各入口统一唤醒场景主窗口，使用 `.moveToActiveSpace` 和普通窗口层级。构建、自动测试与原生现场验证分别记录在开发参考中，不以配置值代替跨桌面验收。
- 下文其余条目从原 AGENTS.md 迁入，保留已有需求与验收细节；迁移不表示本轮重新验证了实现。

## 内容、执行与数据要求

### 正文编辑框自动换行（#54）

- 正文按编辑框实际可用宽度视觉折行，中文、英文、长链接及无空格连续文本不横向溢出；布局宽度变化后重新折行。
- 视觉折行不插入换行符，不改变原文、复制结果或适配器输入；用户手工换行和空行保持原样。本项不改变主窗口不可调整大小的既有约定。

### 全局快捷键显示／隐藏（#37）

- 默认 `⌘＋'`（单引号），在设置的「全局快捷键」中录入其他组合键，清除即停用；修改和停用跨启动保存。仅应用运行时有效，不另行增加常驻辅助进程。
- 快捷键切换同一主窗口的显示／隐藏：窗口在当前桌面且处于前台时收起；窗口隐藏、最小化、被其他应用遮挡或位于其他桌面时唤醒到当前桌面。沿用普通窗口层级，不清空内容、不新建窗口或任务。执行中、等待登录和结束时保持对应状态。菜单栏与其他显式唤醒入口仍按各自既有规则工作。
- 编辑状态从后台唤醒后正文获得焦点；窗口已在前台时保持当前编辑焦点和光标位置，非编辑状态不强制聚焦正文。
- 系统占用或注册失败明确提示，保留所选组合键并允许更换或重试；不能将保存成功当作注册成功，也不承诺识别所有占用快捷键的应用。录入期间临时解绑，结束录入后恢复注册。
- 只注册指定组合键，不要求辅助功能或输入监控权限；正式签名原生验证及未覆盖场景记录在开发参考中。

### 在线更新（#49）

- 默认每天自动检查一次，仅显示标题栏轻量提醒，不主动下载或激活窗口。设置提供自动检查开关、当前版本及手动检查入口。
- 标题栏齿轮保持原位置，更新提示在其左侧，按原型使用绿色圆点、文字和细边框圆角；下载中显示百分比。提示出现、文字变化和消失均不移动齿轮，无提示时不保留额外占位。
- 用户查看版本说明后点击「下载并更新」才下载；展示真实下载与准备进度，下载可取消，收起面板不取消下载。
- 校验与准备完成后等待「重启并使用新版」。由独立辅助进程在旧进程退出后安装并启动新版；不能把下载完成显示为更新成功。
- 正在填写、待登录、交还浏览器、未交接结果或非空标题／正文／图片均阻止更新启动与安装重启。下载后新增内容也必须阻止重启；安装等待期间的退出同样受保护，不清空稿件或配置。
- 使用签名更新清单和签名更新包，验证通过才进入安装。检查、下载或验证失败须明确反馈，不伪报成功；版本比较、辅助安装及重启复用 Sparkle。
- 本地实现与隔离升级验收已完成；正式线上入口须发布含匹配 appcast.xml、签名 ZIP 的 Release 后生效。当前 Inkpost 签名为本地自签名，尚不具备 Apple Developer ID 公证分发资质。

### 发布与素材

- Product content is plain text, supporting line breaks and emoji. When creating the shared task snapshot, trim whitespace and newlines from the outer edges of the entire title and body before passing them to channel adapters (#51). Do not trim individual lines or change internal spaces, tabs, line breaks, blank lines or characters. Preserve the editor's original draft. All channels and login recovery use the same trimmed snapshot; whitespace-only body blocks task creation, and whitespace-only title becomes empty. This supersedes the previous no-trim requirement. Do not render Markdown, generate HTML, use rich-text formatting, or add other content processing features. Local fixtures use plain-text controls as well.

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

- 墨驿在当前用户下仅允许一个应用进程实例，涵盖正常打开、直接执行和不同路径副本。重复启动唤起已有主窗口，不清空内容、修改渠道或重新启动任务；并发启动同样互斥。异常退出后可重新启动；已有实例无法响应时明确提示，不强杀旧实例或启动第二套发布界面。短暂的启动检查不创建编辑状态、任务或菜单栏图标。
- Inkpost has one ordinary NSWindow at normal level using the former compact layout. No compact/full publishing mode or second editor. The former workspace is Settings only; do not add configuration capabilities during this migration.
- Use the native titlebar with title 墨驿, visible standard close/minimize buttons and a disabled gray zoom button; no resizing or fullscreen. Close and minimize both hide the main window without quitting, cancelling, or minimizing to Dock. The right gear opens Settings.
- Clicking the menu-bar icon shows or brings forward the same main window, including when it is covered by another app or belongs to another desktop; visibility alone must never make a click hide it. Explicit opening brings the window to the current desktop without switching desktops, activates once and focuses the body. Switching apps leaves it visible behind other apps, without raising Settings. Do not provide a Dock entry or depend on Dock reopen for access.
- Hide automatically once only after valid Start Filling begins execution. Progress, completion, failure, cancellation, login waiting, focus loss and Escape must not change visibility.
- Main window and Settings share one DispatchController/DispatchModel. Task operations share the same model; the main window shows concise results and one navigation action, without execution logs or raw errors. NativeMenuBar owns status copy and fixed-size image animation; animation ticks never write title or item length. Window lifecycle remains in Views.

- Product workflow ends at awaitingConfirm (已填好); no product UI for published or receipt tracking. On successful workspace handoff, archive the content, images and Space identity in session history, then reset the editor while retaining channel selection. Failed navigation and login-waiting tasks must retain content. Ended tasks with problems also archive/reset only after successful final Space navigation. Internal fixture CLI may retain receipt checks.
- PNG encoding belongs exclusively to AssetService during task preparation, before any adapter/browser execution. DispatchService retains one complete prepared batch per task and passes its source-to-PNG mapping through ChannelExecutionContext while preserving the original ChannelRequest. Adapters upload only those PNG files; adapter-side or clipboard-side format conversion, repair, and fallback to originals are forbidden. Resume reuses the same batch; release it only after no invocation can use it. Reject unsupported animated/multiframe assets explicitly, never silently flatten them.
- Assets use AssetService for validation and byte-based SHA-256 deduplication. The editor's current six-image selection limit is a product-level constraint, independent of each channel's supported image count. Pass every selected image to each selected adapter; the adapter reports any channel-specific excess rather than silently selecting a subset. Temporary assets are not durable drafts.
- Image sorting drops insert the source immediately before the target, with an insertion marker at the target's leading edge. Dropping onto itself, cancelling or rejecting a drag preserves content and order; ending the drag clears its visual state. Sorting is disabled outside the pending editor phase. Display, model and complete channel requests use the same ordered assets; external image import is separate from internal sorting.
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
- Dispatch passes the title and body from the shared task snapshot after the common edge trim, preserving explicit HTML and ordered source assets in ChannelRequest. Dispatch does not generate HTML. Task-prepared PNG mappings stay separate from the request.

## Deterministic channel execution

- LLM clients, tool-use loops and model configuration have been removed. Dispatch contracts carry content and execution identity only.
- Zhihu, Jike, X and the local fixture use deterministic workflows. Read `Sources/PublishKit/Services/Channels/JikeChannelAdapter.md` before changing Jike; keep its inline composer, exact text verification and ordered attachment recovery within its adapter.

## Weibo channel

- Weibo opens the Quick Publish panel from the homepage “发微博” button, waits for automatic focus, and uses panel-scoped native body/PNG paste and ordered remote attachment checkpoints. Read [Weibo adapter maintenance](../Sources/PublishKit/Services/Channels/WeiboChannelAdapter.md) before changing it. A nonempty title is prepended to the body with one newline, preserving both fields exactly; an empty title adds no newline. Explicit HTML is unused and the original request remains intact. Preserve existing page drafts; do not enter long-article mode or click Send.

## Juejin pins channel

- Read [Juejin adapter maintenance](../Sources/PublishKit/Services/Channels/JuejinChannelAdapter.md) before changing it. Ordinary pins only; title is optionally prepended with one newline, composed text at most 1000 UTF-16 units. First filling clears old body/attachments as authorized; resume must never clear again. Preserve the received task input after the common edge trim; the website itself trims edge whitespace on submission. Attachments are staged locally and uploaded only by the user’s final Publish action; verify all staged images without claiming remote upload.

## 异常结果展示与导航（#47，历史方案）

以下记录 0.15.0 的方案；渠道入口、登录恢复和最终导航以 #48 的最新规则为准。

- 主窗口任务结果区只保留一个前往按钮和静态结果说明，不展示执行日志、原始技术报错、渠道重试按钮、重复渠道卡片或修改未完成内容入口。执行中的停止填写能力保留。
- 有异常时按钮为「前往处理」，说明如「4 个已填好 · 微博需处理」；多个异常列出名称，全部需处理时汇总数量。全部已填好时保留「已完成，前往发布」，最终发布仍由用户手工操作。
- 前往处理优先定位本任务按任务顺序第一个未完成渠道的原 Page；其他渠道在同一个 ego 工作区切换。导航不重新填写、不新建渠道页面、不修改真实渠道结果，不清空未完成稿。
- 原 Page 不可用时给出短提示，同一个按钮改为「打开工作区」；打开失败保留内容和入口，不静默跳首页。执行或交还中不并发开启导航、恢复、重置或编辑未完成任务。
- 日志仍保留在内部诊断数据中，移除界面展示不等于吞掉执行错误。恢复自动填写的后续交互不在本项重新设计。

## 渠道状态与填写交接（#48）

- 采用 `prototypes/inkpost-completion-handoff.html` 已确认方案。渠道标签内用无背景线性图标显示填写中、填写成功、需登录、其他问题；图标具有文字提示与无障碍说明。编辑时标签选择渠道，任务中冻结选择，登录/问题图标独立点击打开该任务对应的原渠道 Page。
- 有待登录渠道时主按钮「我已登录，继续」。点击后只恢复登录等待渠道，复用原输入快照、任务、Space 和 Page；已填好渠道不重复执行。普通异常不自动重试，也不把超时推断为未登录。可跳过剩余待登录渠道转为手工处理。
- 等待登录是过程状态，不发最终完成通知、不完成 Space。其他渠道继续本轮填写；若执行中点击登录/问题图标，导航请求先排队，待本轮其他渠道停止自动操作后才打开目标 Page 并交还整个 Space，避免用户与 Agent 同时操作。
- 全部填好：主按钮「已填写，需要你手工发布」；存在其他问题、跳过或取消：主按钮「去查看」。自动流程结束后完成 ego Space 并保留页面交还控制权；仅表示填写结束，不表示内容已发布。控制权交还失败必须明确提示，不能伪报成功。
- 最终主按钮打开本次任务 Space，成功后归档并清空标题、正文、图片，保留渠道选择；打开失败保留内容与重试入口。渠道图标只导航，不重置、不改变渠道结果。通知导航不清空其他任务。
- 自动填写已结束且最终打开工作区失败时，在报错后同排显示轻量文字按钮「我已处理，忽略」。点击无需二次确认，不再访问 ego，直接清空标题、正文、图片及本次任务状态，保留渠道选择并恢复正文焦点；执行中、等待登录或导航进行中不可用。
- 完成后的 Space 不可继续填写；原 Page 标签失效时，只能通过保存的唯一页面身份重新定位，无法唯一确认时明确报错，不跳其他渠道或首页。无消散动画。

## B站普通图文动态（#29）

- 入口为 `https://t.bilibili.com/`；标题选填、正文必填、图片选填。标题与正文分别先点击对应输入元素获得焦点，再粘贴并回读核对，停在发布按钮前，用户手工发布。
- 首次填写前清空 B站编辑区原有标题、正文和图片，确认清空后再填写。恢复时不重复清空或粘贴，复用原 Page 和有序图片检查点；公共分发不增加 B站专属分支。
- 平台正文须与适配器收到的任务输入一致（公共层已统一去除整段首尾空白）；若平台另行改动内容，明确要求用户检查，不静默改写或报告填写成功。具体页面规则和验收边界见 [B站适配器维护](../Sources/PublishKit/Services/Channels/BilibiliChannelAdapter.md)。
