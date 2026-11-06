# 墨驿 Inkpost

当前版本：`0.4.0`

> 「墨」承文脉，「驿」管送达——内容驿站：一次投递，各平台分发。

Mac 上的多平台内容分发台：**App 内置极简 agent，驱动 ego lite 浏览器把内容填进各平台创作页，停在草稿，人工确认发布。**

```
┌─────────────────────────────────────────────────────┐
│ Inkpost.app (SwiftUI)                               │
│  菜单栏 → 简约填写 → 渠道进度 → 人工处理 → 已填好 │
│                                                     │
│  AgentLoop（~200 行）                                │
│   · OpenAI 兼容 tool-use 循环（默认 DeepSeek）        │
│   · 提示词约定：只填草稿，人工确认发布   │
│                                                     │
│  EgoBridge（工具层）                                  │
│   · navigate/snapshot/fill/paste_html/upload/…       │
│   · 每个工具 = 一次 ego-browser 官方调用               │
└─────────────────────────────────────────────────────┘
                    ↓ 驱动                ↑ 人工确认发布
              ego lite（用户已登录的浏览器工作区）
```

## 设计原则

1. **人是最后一环**：通过提示词要求 agent 只准备草稿，由用户检查并亲手发布；现有通用点击与脚本工具并未从权限层阻止发布，提示词不是可强制执行的安全边界。
2. **App 自己当 agent**：不依赖外部 agent CLI；LLM 走 OpenAI 兼容 API（DeepSeek/GLM/任何兼容端点），key 由用户配置，存 UserDefaults（后续升级 Keychain）。
3. **零第三方依赖**：SPM 无外部包；LLM 客户端与 agent 循环手写（标准协议，~300 行）。
4. **工具层确定性可测**：EgoBridge 不依赖 LLM 即可单独驱动（见 `flowctl agent-demo`，内置假模型）。

## 运行

前置：安装 [ego lite](https://lite.ego.app/) 并完成首次引导（`ego-browser` 命令可用）；App 内已登录/可登录目标平台。

```bash
cd inkpost
swift build

# 界面版
swift run PublishFlow

# CLI 冒烟（假模型，无需 API key）
swift run flowctl agent-demo   # 极简 agent 管道验证
swift run flowctl cleanup      # 清理测试遗留的 ego TaskSpace
```

界面版使用：菜单栏打开墨驿 → 右上角进入完整界面配置 DeepSeek API Key → 填写内容、添加图片并选择渠道 →「填写到所选渠道」→ 需要时手工处理异常 →「已填好，前往确认并发布」→ 在 ego Lite 中亲手发布。

## 当前状态

- ✅ 极简 agent 管道端到端（fixture 模拟平台，含回执回读）
- ✅ 最小 UI（DeepSeek 配置 / 内容编辑 / 分发 / 日志 / 确认卡点）
- 🚧 真实平台适配（知乎/小红书/微博/即刻/X——同一套工具，仅目标 URL 与页面认知不同）
- 🚧 API Key 移入 Keychain；定时分发；多平台组合；数据回流

## 目录

```
Sources/PublishKit/
  Models.swift          任务/状态数据结构（PublishTask 协议）
  EgoLiteEngine.swift   ego-browser 进程执行器（官方 stdin 调用规范）
  EgoBridge.swift       工具层（官方 helper 封装，可独立测试）
  AgentLoop.swift       LLM 消息/工具协议定义
  AgentLoopRuntime.swift OpenAI 兼容客户端 + 极简 agent 循环 + 假模型
  MarkdownLite.swift    最小 Markdown→HTML
  PostStore.swift       本地存储（Application Support/PublishFlow/posts）
  Adapters/             simulate-human.mjs 等 CLI 冒烟辅助
  Fixtures/             模拟平台页面
  DispatchModel.swift   可观察内容、配置与运行状态（不依赖 UI）
  PlatformRules.swift   平台目标提示词（保持现有分发行为）
  Controllers/         DispatchController：协调服务并更新 Model
  Services/            AgentDispatchService / DispatchSettings
Sources/PublishFlow/
  PublishFlowApp.swift  依赖组装与 Scene 入口
  Views/                所有 UI，包括组件、样式、弹窗与文件选择器
Sources/flowctl/        CLI（agent-demo / prepare / finalize / cleanup）
```

## 架构约定

采用适配 SwiftUI 的 MVC + Services：View → Controller → Model / Services，View 观察 Model 自动刷新。所有 UI 都放在 Views 中；Controller 不依赖 SwiftUI 或 AppKit，也不实现浏览器脚本、HTTP 或文件读写。平台任务状态统一使用 PublishKit.TargetPhase。

知乎想法使用固定流程：打开首页「分享此刻的想法」，填写完整正文及标签，再将应用图片逐张复制为系统剪贴板 PNG，通过 ego Lite 的 ⌘V 粘贴；每张确认上传完成后再继续。按附件卡片核对数量，仅在应用仍拥有剪贴板变更计数时恢复原内容，保留用户期间的新复制；同一任务恢复不会再次插入已确认的图片。结果不确定时停止并提示检查，最终由用户亲手发布；不使用独立标题，不进入文章页，也不保证平台已持久保存草稿。

GUI 与 CLI 的 agent-demo 共用 AgentDispatchService.run，Controller 可注入 DispatchServicing 替身进行离线验证。现有确定性 prepare/finalize CLI 适配器保留。帖子持久化尚未接入；简约模式开发已修复正文截断、统一状态，并把模型任意 JS 工具替换为固定只读检查。

验证：`swift build`、`swift test`（Swift Testing；CLT 环境补充命令见下文），以及安装 ego Lite 后的 `swift run flowctl agent-demo`。如果旧缓存记录了仓库改名前的路径，可使用 `--scratch-path /tmp/inkpost-mvc-build` 构建与测试，无需删除原缓存。

## 参考

- ego lite 官方文档：https://lite.ego.app/document/en/docs/ego-browser（调用规范：stdin 单脚本 + 官方 helper）
- 同类模式的开源项目：BloopAI/vibe-kanban、getAsterisk/opcode、ttnear/Clarc（SwiftUI 原生调 Claude Code）

## 简约模式（本地开发版）

设置 `INKPOST_SIGNING_IDENTITY` 为已配置的正式代码签名身份，再运行 `bash Scripts/make-app.sh`（不允许临时签名；签名验证通过后替换旧进程并检查启动）。墨驿是正常显示 Dock 和应用菜单的前台应用，启动时保留主窗口；菜单栏只是快捷入口，点击图标展开 420pt 快速填写界面并激活应用，使编辑区能够接收键盘输入与粘贴。右上角进入完整工作台，在偏好设置中配置 DeepSeek；两种界面共享内容。关闭完整窗口不退出应用，可通过原生应用菜单或 ⌘Q 退出。

- 本地多选 / 正文粘贴图片（含 Finder 复制的图片文件），最多 6 张；按字节内容去重，合并报告新增、重复及超量数量，支持预览、移除与排序；附件保存在系统临时目录，不保证退出或系统清理后的恢复。
- 渠道按原型采用 6 列栅格，向上取 1/2/3 格并保存上次选择。实际可选知乎、即刻、X；其余候选保留原型配色，点击提示待适配，不参与分发。
- 正文底部固定工具区提供「清空」与字数，正文独立滚动；空正文时清空不可用。
- 状态为等待开始、正在填写、需要您手工处理、已填好。填写中按钮跟随当前渠道滚动，结束或异常给出站内提示；打包 App 获得通知权限后才发系统提醒。
- 一次任务共用一个 ego Lite Space，各渠道绑定 Page 标签；人工检查时交还控制，用户处理后在完整工作台的渠道卡片继续单个异常渠道；简约界面只提供主操作与状态说明，修改未完成内容在完整工作台操作；全部已填好并成功交还工作区后自动开始新一份。投递记录显示本次运行中已交接的内容、图片和工作区编号，以及当前任务渠道状态，不展示执行日志。恢复时模型需重新检查原页面，复杂编辑器恢复仍需实测。
- 模型不再获得任意 JavaScript 求值工具；固定只读检查回读正文、标题、图片数量。平台无法可靠提供选择器或校验不符时转人工处理，不误报已填好。
- 真实平台页面会变化，尚未做全平台回归；不会以测试为由向真实平台发布。

设计与计划：`prototypes/inpost-prototype-简约模式.html`、`docs/plans/compact-mode-implementation.md`。

### 验证

完整 Xcode 环境可运行 `swift build`、`swift test`。当前开发机只有 Command Line Tools，其 XCTest 不可用，测试已采用随工具链提供的 Swift Testing。若遇到模块路径错误，可用以下命令（路径以本机工具链为准）：

```bash
swift test --disable-xctest --scratch-path /tmp/inkpost-compact-build \
  -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks
```

项目改名前遗留的 `.build` 缓存可能引用旧目录；使用新的 `--scratch-path`，无须删除现有缓存。浏览器冒烟：`swift run --scratch-path /tmp/inkpost-compact-build flowctl compact-smoke`，验证同 Space 双 Page、正文与图片，不点击发布；`agent-demo` 保留模拟人工确认的历史管道演示。

点击「已填好」成功交还 ego 工作区后，编辑区恢复初始并保留渠道选择；上一份内容、图片和 Space 编号可在投递记录中查看。记录仅在本次运行内保留，不追踪发布结果；交接失败或存在未完成渠道时不清空。下一次填写使用新的 Space。


仅选择知乎想法时无需 API Key 或标题；即刻和 X 仍需模型配置，X 最多 4 张图片。完整工作台提供可展开的执行日志与渠道错误详情。

### 渠道适配器（#9）

`Services/Channels/` 按渠道隔离知乎、即刻、X 和模拟平台。`ChannelAdapter` 统一接收 `ChannelRequest`（标题、完整正文、HTML、标签、素材），声明标题／模型配置需求、图片上限和入口，并负责准备、校验和恢复状态。知乎保留确定性想法流程，其余渠道复用 Agent 执行器。

`AgentDispatchService` 通过 `ChannelRegistry` 查找适配器，负责一个任务的 Space 和各渠道 Page，不包含平台步骤。注册表随新任务创建，恢复时复用原适配器与 Page；Controller 根据能力声明进行启动校验。`PlatformRules` 和历史 prepare 重载保留为兼容入口，生产 Controller 不再构造平台提示词。通用 `EgoBridge` 不含知乎分支，PNG 剪贴板保存与有条件恢复由 `ImageClipboardSession` 复用。

新增渠道：实现适配器并注册，再补充平台标识及展示信息；无需修改核心调度算法。适配器测试使用注入的 Page 工厂，无浏览器／API Key 验证结构化输入、独立失败、页面复用、新任务隔离和能力限制。真实平台仍只填好内容，不自动发布。
