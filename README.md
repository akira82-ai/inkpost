# 墨驿 Inkpost

当前版本：`0.8.1`

> 「墨」承文脉，「驿」管送达——内容驿站：一次投递，各平台分发。

Mac 上的多平台内容分发台：**App 通过确定性渠道适配器驱动 ego lite 浏览器把内容填进各平台创作页，停在草稿，人工确认发布。**

```
┌─────────────────────────────────────────────────────┐
│ Inkpost.app (SwiftUI)                               │
│  菜单栏 → 简约填写 → 渠道进度 → 人工处理 → 已填好 │
│                                                     │
│  ChannelAdapter（渠道独立流程）                                │
│   · 固定网页操作与内容回读校验        │
│   · 只填写内容，最终发布由用户操作   │
│                                                     │
│  EgoBridge（工具层）                                  │
│   · navigate/snapshot/fill/paste_html/upload/…       │
│   · 每个工具 = 一次 ego-browser 官方调用               │
└─────────────────────────────────────────────────────┘
                    ↓ 驱动                ↑ 人工确认发布
              ego lite（用户已登录的浏览器工作区）
```

## 设计原则

1. **人是最后一环**：适配器停在已填好，由用户检查并亲手发布；浏览器工具本身并不构成禁止发布的权限沙箱。
2. **确定性执行**：渠道独立维护网页操作、验证与恢复，不依赖模型服务或密钥。
3. **零第三方依赖**：SPM 无外部包，复用 ego Lite 浏览器能力。
4. **可测试**：Controller 可注入服务替身，适配器可注入浏览器传输。

## 运行

前置：安装 [ego lite](https://lite.ego.app/) 并完成首次引导（`ego-browser` 命令可用）；App 内已登录/可登录目标平台。

```bash
cd inkpost
swift build

# 界面版
swift run PublishFlow

# CLI 冒烟（只操作本地 fixture，不发布）
swift run flowctl compact-smoke
swift run flowctl cleanup      # 清理测试遗留的 ego TaskSpace
```

界面版使用：菜单栏打开墨驿 → 右上角进入完整界面 → 填写内容、添加图片并选择渠道 →「填写到所选渠道」→ 需要时手工处理异常 →「已填好，前往确认并发布」→ 在 ego Lite 中亲手发布。

## 当前状态

- ✅ 确定性浏览器工具与本地 fixture 流程
- ✅ 最小 UI（内容编辑 / 分发 / 日志 / 确认卡点）
- 已接入知乎、即刻和 X，均采用确定性适配器；其他渠道待开发。
- 🚧 定时分发、数据回流与持久化恢复尚未实现。

## 目录

```
Sources/PublishKit/
  Models.swift          任务/状态数据结构（PublishTask 协议）
  EgoLiteEngine.swift   ego-browser 进程执行器（官方 stdin 调用规范）
  EgoBridge.swift       工具层（官方 helper 封装，可独立测试）
  MarkdownLite.swift    最小 Markdown→HTML
  PostStore.swift       本地存储（Application Support/PublishFlow/posts）
  Adapters/             simulate-human.mjs 等 CLI 冒烟辅助
  Fixtures/             模拟平台页面
  DispatchModel.swift   可观察内容与运行状态（不依赖 UI）
  PlatformRules.swift   通用输入规则（正文、标题需求、图片上限）
  ChannelContract.swift 固定命令、事件、结果、错误与恢复动作
  Controllers/         DispatchController：协调服务并更新 Model
  Services/            DispatchService / DispatchSettings
Sources/PublishFlow/
  PublishFlowApp.swift  依赖组装与 Scene 入口
  Views/                所有 UI，包括组件、样式、弹窗与文件选择器
Sources/flowctl/        CLI（compact-smoke / prepare / finalize / cleanup）
```

## 架构约定

采用适配 SwiftUI 的 MVC + Services：View → Controller → Model / Services，View 观察 Model 自动刷新。所有 UI 都放在 Views 中；Controller 不依赖 SwiftUI 或 AppKit，也不实现浏览器脚本、HTTP 或文件读写。平台任务状态统一使用 PublishKit.TargetPhase。

知乎想法使用固定流程：打开首页「分享此刻的想法」，有标题则填写并回读核对，再一次性粘贴完整正文及标签，再将任务预先准备的 PNG 图片逐张复制到系统剪贴板，通过 ego Lite 的 ⌘V 粘贴；每张确认上传完成后再继续。按附件卡片核对数量，仅在应用仍拥有剪贴板变更计数时恢复原内容，保留用户期间的新复制；同一任务恢复不会再次插入已确认的图片。结果不确定时停止并提示检查，最终由用户亲手发布；标题可空，有则填写独立标题，不进入文章页，也不保证平台已持久保存草稿。

GUI 使用 DispatchService 与渠道适配器，Controller 可注入 DispatchServicing 替身进行离线验证。确定性 prepare/finalize CLI 适配器保留，仅用于本地 fixture；帖子持久化尚未接入。

验证：`swift build`、`swift test`（Swift Testing；CLT 环境补充命令见下文），以及安装 ego Lite 后的 `swift run flowctl compact-smoke`。如果旧缓存记录了仓库改名前的路径，可使用 `--scratch-path /tmp/inkpost-mvc-build` 构建与测试，无需删除原缓存。

## 参考

- ego lite 官方文档：https://lite.ego.app/document/en/docs/ego-browser（调用规范：stdin 单脚本 + 官方 helper）
- 同类模式的开源项目：BloopAI/vibe-kanban、getAsterisk/opcode、ttnear/Clarc（SwiftUI 原生调 Claude Code）

## 简约模式（本地开发版）

设置 `INKPOST_SIGNING_IDENTITY` 为已配置的正式代码签名身份，再运行 `bash Scripts/make-app.sh`（不允许临时签名；签名验证通过后替换旧进程并检查启动）。墨驿是正常显示 Dock 和应用菜单的前台应用，启动时保留主窗口；菜单栏只是快捷入口，点击图标展开 420pt 快速填写界面并激活应用，使编辑区能够接收键盘输入与粘贴。右上角进入完整工作台；两种界面共享内容。关闭完整窗口不退出应用，可通过原生应用菜单或 ⌘Q 退出。

- 上传前统一准备真实 PNG，保留原文件、图片顺序、尺寸、方向和透明度；同一任务的各渠道及恢复复用该批素材。损坏或无法解码的图片、动图和多帧图片会在浏览器执行前明确报错，不跳过或上传原格式。
- 本地多选 / 正文粘贴图片（含 Finder 复制的图片文件），最多 6 张；按字节内容去重，合并报告新增、重复及超量数量，支持预览、移除与排序；附件保存在系统临时目录，不保证退出或系统清理后的恢复。
- 渠道按原型采用 6 列栅格，向上取 1/2/3 格并保存上次选择。实际可选知乎、即刻、X；其余候选保留原型配色，点击提示待适配，不参与分发。
- 正文底部固定工具区提供「清空」与字数，正文独立滚动；空正文时清空不可用。
- 状态为等待开始、正在填写、需要您手工处理、已填好。填写中按钮跟随当前渠道滚动，结束或异常给出站内提示；打包 App 获得通知权限后才发系统提醒。
- 一次任务共用一个 ego Lite Space，各渠道绑定 Page 标签；人工检查时交还控制，用户处理后在完整工作台的渠道卡片继续单个异常渠道；简约界面只提供主操作与状态说明，修改未完成内容在完整工作台操作；全部已填好并成功交还工作区后自动开始新一份。投递记录显示本次运行中已交接的内容、图片和工作区编号，以及当前任务渠道状态，不展示执行日志。恢复时适配器重新检查原页面，复杂编辑器恢复仍需实测。
- 通过只读检查回读正文、标题、图片数量。平台无法可靠提供选择器或校验不符时转人工处理，不误报已填好。
- 真实平台页面会变化，尚未做全平台回归；不会以测试为由向真实平台发布。

设计与计划：`prototypes/inpost-prototype-简约模式.html`、`docs/plans/compact-mode-implementation.md`。

### 验证

完整 Xcode 环境可运行 `swift build`、`swift test`。当前开发机只有 Command Line Tools，其 XCTest 不可用，测试已采用随工具链提供的 Swift Testing。若遇到模块路径错误，可用以下命令（路径以本机工具链为准）：

```bash
swift test --no-parallel --disable-xctest --scratch-path /tmp/inkpost-compact-build \
  -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks
```

测试涉及进程级剪贴板租约，使用 `--no-parallel` 避免独立用例相互争用。

项目改名前遗留的 `.build` 缓存可能引用旧目录；使用新的 `--scratch-path`，无须删除现有缓存。浏览器冒烟：`swift run --scratch-path /tmp/inkpost-compact-build flowctl compact-smoke`，验证同 Space 双 Page、正文与图片，不点击发布。

点击「已填好」成功交还 ego 工作区后，编辑区恢复初始并保留渠道选择；上一份内容、图片和 Space 编号可在投递记录中查看。记录仅在本次运行内保留，不追踪发布结果；交接失败或存在未完成渠道时不清空。下一次填写使用新的 Space。


知乎想法和 X 的标题可空；即刻使用关注页内的「分享你的想法…」编辑器，原生粘贴正文，使用图片选择器逐张上传并回读校验，标题与 HTML 不使用，停在发送前。X 直接打开撰写页，标题有则拼到正文第一行，正文及标签原生粘贴，最多逐张粘贴 4 张图片；组合文本按产品约定最多 1899 字，并检查实际账号的编辑器接受状态，最终由用户发布。完整工作台提供可展开的执行日志与渠道错误详情。

### 渠道适配器（#9）

`Services/Channels/` 按渠道隔离知乎、即刻、X 和模拟平台。`ChannelAdapter` 统一接收 `ChannelRequest`（标题、完整正文、HTML、标签、素材），声明标题需求、图片上限和入口，并负责准备、校验和恢复状态。所有已注册适配器均使用确定性流程。

`DispatchService` 通过 `ChannelRegistry` 查找适配器，负责一个任务的 Space 和各渠道 Page，不包含平台步骤。注册表随新任务创建，恢复时复用原适配器与 Page；Controller 根据能力声明进行启动校验。移除了历史 goal/prepare 重载及主流程二次校验入口；`PlatformRules` 仅校验领域输入，Controller 不构造平台提示词。通用 `EgoBridge` 不含知乎分支，PNG 剪贴板保存与有条件恢复由 `ImageClipboardSession` 复用。

新增渠道：实现适配器并注册，再补充平台标识及展示信息；无需修改核心调度算法。适配器测试使用注入的 Page 工厂，无需浏览器 验证结构化输入、独立失败、页面复用、新任务隔离和能力限制。真实平台仍只填好内容，不自动发布。

### 适配器通信契约

主流程通过 `DispatchServicing.execute` 发送结构化内容及 `prepare` / `resumeAfterUser` 命令；适配器通过 `ChannelExecutionContext` 上报固定阶段、计数进度和诊断事件，返回 `readyForReview`、`waitingForUser` 或 `failed`。错误包含稳定的 `code`、`stage`、`recovery`、具体说明及诊断编号，主流程按枚举处理，展示文案放在 Views。这里使用进程内类型协议，不引入消息队列或事件总线。

`readyForReview` 表示适配器已回读校验完整的渠道转换结果：正文及标签、渠道需要的标题和图片数量。知乎另外逐张等待附件完成；通用图片校验仅证明数量，不证明图片身份或平台持久保存。正文校验保留用户空白，具体逻辑块规则由渠道定义；平台富文本换行与预期不同会转人工检查，不自动忽略差异或改写内容。

每次调用带任务／渠道／尝试编号；迟到回调不会覆盖当前状态。恢复只接受原内容快照和允许恢复的结果，复用原适配器与 Page。新的任务重建会话。取消停止后续工具和渠道，保留内容；已经发送给浏览器的动作可能完成，取消不等于撤销。填写／上传结果不明时返回 `operationResultUnknown + inspectionRequired`，要求先检查页面再继续，避免自动重复粘贴。完整界面提供停止填写操作。

共享原生粘贴服务提供互斥租约，PNG 写入按变更计数恢复剪贴板，ego Lite 的文本粘贴使用其原生恢复机制；两者不应同时占用剪贴板。

测试覆盖结构化内容、登录恢复、快照不变性、重复命令、新任务隔离、过期回调、取消传播、剪贴板互斥／恢复以及真实 Fixture 适配器对漏填内容的拒绝。设置 `INKPOST_BROWSER_TESTS=1` 后运行上述 `swift test`，还会通过真实 ego Lite 执行本地 Fixture 适配器（确定性执行），回读标题／正文／标签／图片并确认没有发布；默认跳过此浏览器测试。真实渠道的登录过期、网络故障及复杂富文本仍需专项回归。

知乎适配器按逻辑编辑块核对完整正文、空格和空段落，避免 innerText 的视觉换行误差。恢复前核对已有标题、正文及已确认附件的远程标识和顺序；发现冲突保留页面并转人工检查，不盲目重复粘贴。平台未声明标题上限时不自行编造限制，实际填写后回读确认。

当前边界待跟进：Controller 仍可能因缺少正文／标题阻止整批开始，PlatformRules 仍在适配器调用前执行渠道校验。这些行为尚未达到全部渠道规则独立归适配器的目标。旧的 prepare/goal、独立 verify 接口已移除，库调用方需迁移到 execute 和 ChannelOutcome。0.7.0 同时移除 LLMConfig、模型配置参数及 agent-demo 命令，AgentDispatchService 更名为 DispatchService。

知乎输入约束：标题可空，有则填写，少于 45 字（最多 44）；正文必填，连同追加标签和换行少于 1900 字（最多 1899）；图片可空。按 Swift String.count 的用户可见字符计数，中文一个字计一个字符；超限明确报错，不截断、不生成标题。

主流程现保留正文原始 Markdown 与空白后传入每个适配器；HTML 仍由主流程生成，标签仍经拆分及去除井号处理，#13 尚未全部完成。
