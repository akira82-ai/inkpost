# 墨驿 Inkpost

> 「墨」承文脉，「驿」管送达——内容驿站：一次投递，各平台分发。

Mac 上的多平台内容分发台：**App 内置极简 agent，驱动 ego lite 浏览器把内容填进各平台创作页，停在草稿，人工确认发布。**

```
┌─────────────────────────────────────────────────────┐
│ Inkpost.app (SwiftUI)                               │
│  内容表单 → 平台勾选 → 分发 → 进度日志 → 确认卡点 → 回执 │
│                                                     │
│  AgentLoop（~200 行）                                │
│   · OpenAI 兼容 tool-use 循环（默认 DeepSeek）        │
│   · 提示词契约：只填草稿，绝不点击发布 ← 物理安全边界   │
│                                                     │
│  EgoBridge（工具层）                                  │
│   · navigate/snapshot/fill/paste_html/upload/…       │
│   · 每个工具 = 一次 ego-browser 官方调用               │
└─────────────────────────────────────────────────────┘
                    ↓ 驱动                ↑ 人工确认发布
              ego lite（用户已登录的浏览器工作区）
```

## 设计原则

1. **人是最后一环**：agent 物理上没有"发布"工具，只能把内容准备成草稿；发布按钮永远由用户亲手点击。
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
Sources/PublishFlow/    SwiftUI App（最小 UI）
Sources/flowctl/        CLI（agent-demo / prepare / finalize / cleanup）
```

## 参考

- ego lite 官方文档：https://lite.ego.app/document/en/docs/ego-browser（调用规范：stdin 单脚本 + 官方 helper）
- 同类模式的开源项目：BloopAI/vibe-kanban、getAsterisk/opcode、ttnear/Clarc（SwiftUI 原生调 Claude Code）
