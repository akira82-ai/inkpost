# 墨驿 Inkpost

当前版本：`0.1.1`

> 「墨」承文脉，「驿」管送达——内容驿站：一次投递，各平台分发。

Mac 上的多平台内容分发台：**App 内置极简 agent，驱动 ego lite 浏览器把内容填进各平台创作页，停在草稿，人工确认发布。**

```
┌─────────────────────────────────────────────────────┐
│ Inkpost.app (SwiftUI)                               │
│  内容表单 → 平台勾选 → 分发 → 进度日志 → 确认卡点 → 回执 │
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

界面版使用：左栏填入 DeepSeek API Key（模型默认 `deepseek-chat`，地址固定 `https://api.deepseek.com`）→ 添加图片 → 右栏写标题/正文(Markdown)/话题 → 「开始分发」→ 观察 agent 日志 → 到 ego 浏览器检查草稿并亲手发布 → 回到 App 点「读取回执」。

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

GUI 与 CLI 的 agent-demo 共用 AgentDispatchService.run，Controller 可注入 DispatchServicing 替身进行离线验证。现有确定性 prepare/finalize CLI 适配器保留。本轮仅拆分职责，尚未接入帖子持久化、修复正文截断或加强发布权限。

验证：`swift build`、`swift test`（需包含 XCTest 的 Xcode 开发环境），以及安装 ego Lite 后的 `swift run flowctl agent-demo`。如果旧缓存记录了仓库改名前的路径，可使用 `--scratch-path /tmp/inkpost-mvc-build` 构建与测试，无需删除原缓存。

## 参考

- ego lite 官方文档：https://lite.ego.app/document/en/docs/ego-browser（调用规范：stdin 单脚本 + 官方 helper）
- 同类模式的开源项目：BloopAI/vibe-kanban、getAsterisk/opcode、ttnear/Clarc（SwiftUI 原生调 Claude Code）
