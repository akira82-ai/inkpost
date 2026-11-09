# 开发参考资料

以下内容从 AGENTS.md 移出，保留为既有技术方案与操作参考，不作为新需求的约束，也不代表这些方案必须继续沿用。涉及变更时以用户确认的需求、当前代码和实际验证结果为准。

## 代码组织

- 采用 SwiftUI 适配的 MVC、独立服务与渠道适配器；沿用 macOS 14+、Swift Package Manager 技术栈，优先复用现有实现。
- `Sources/PublishFlow/PublishFlowApp.swift` 是依赖组装与 Scene 入口。
- `Sources/PublishFlow/Views/` 管理 UI、展示文案和窗口生命周期；观察模型并向控制器发送动作，不直接调用浏览器或存储。
- `Sources/PublishKit/DispatchModel.swift`、`Models.swift` 管理状态和领域数据，不依赖 SwiftUI/AppKit；复用已有状态类型。
- `Sources/PublishKit/Controllers/` 协调流程、恢复、取消和重置，不实现 UI、浏览器脚本、HTTP 或文件 I/O。
- `Sources/PublishKit/Services/` 实现外部执行与配置；浏览器、资产、存储操作复用现有服务。
- `Services/Channels/` 的适配器封装渠道实现，通过 `ChannelRegistry` 注册；主流程保持渠道无关，不写渠道名称分支或平台操作细节。
- 输入输出使用结构化契约，流程判断依据状态码和恢复类型，不依赖展示文案；展示文案属于 Views。
- 重构保持当前需求语义；功能变更单独说明，不夹带内容处理、持久化或新平台工作。

## 验证与维护

- 使用内置 Swift Testing，按改动影响运行现有测试；服务依赖可注入，协调测试不依赖真实浏览器或密钥。
- 代码变更验证 `swift build`、`swift test`；涉及浏览器流程且 ego Lite 可用时运行本地 fixture 冒烟，不在真实平台发布。
- CLT-only 环境的 framework 路径和 cross-import overlays 配置见 README。
- 改渠道前阅读对应的 `Sources/PublishKit/Services/Channels/*ChannelAdapter.md`，改动后同步维护；根文档不重复渠道细节。
- 保留完整请求交付、校验、成功、等待人工、结构化失败与恢复、取消和过期结果拒绝的契约覆盖；渠道行为通过真实适配器验证，避免只测替身服务。
- 验证实际后置条件，不能把已发出操作当作成功；不把提示词限制声称为可强制执行的安全边界。

## 原型交付规范

- Organize HTML prototypes vertically into three sections in this order:
  1. Top: a working visual preview, including animations and operable interactions, for the user to experience the design.
  2. Middle: requirements, features, capabilities, and states, explaining behavior and details. Clearly distinguish implemented, simulated, and planned capabilities.
  3. Bottom: design specifications and workflow explanations for developer reference.
- Keep explanatory and developer-reference sections outside the simulated product UI. Keep all three sections consistent when updating the prototype.

## Browser workflow reliability

- The following browser rules apply to browser-based adapter implementations and their shared browser tools, not to the main dispatch algorithm. Follow the installed ego-browser skill and its current `ego-browser skill` guide. The skill is an operating contract; application code must explicitly implement that contract rather than assume skill installation controls runtime behavior.
- For a new or ambiguous platform flow, start with the user's explicit interaction guidance, verify it in the real browser, then encode the proven steps as a deterministic platform workflow. Reuse verified workflows without asking the user to guide each run.
- DOM/semantic targeting and ego Lite operations are complementary: observe a snapshot, identify a unique element by semantic locator or verified selector, perform the documented click/fill/keyboard operation, then verify the result. Snapshot refs are transient and must not be hardcoded across page changes or runs.
- Prefer website-native interactions over JavaScript that mutates DOM or editor internals. Read-only DOM inspection is appropriate for diagnosis and verification. Use coordinates only when usable semantic targeting is unavailable; do not guess selectors or navigate to unrelated creation modes after repeated failures.
- For clipboard images, prefer focusing the intended editor and sending `Meta+V` through ego Lite while the image is already on the system clipboard. `keyboard.paste(text/html)` is a different operation and does not supply image clipboard data. Use system-level key automation only if the documented ego Lite path is demonstrated insufficient.
- Verify meaningful postconditions before advancing: editor expanded, text present, image attachment uploaded. A dispatched action is not proof of success. Count actual attachments rather than raw `img` nodes; previews can live outside the text editor and contain duplicate image nodes.
- On an unexpected page or missing capability, preserve content, report the failing step and concrete error, and diagnose before changing the workflow. Log navigation destinations and tool errors without credentials or sensitive clipboard contents.
