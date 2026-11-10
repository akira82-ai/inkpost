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

## 主窗口与菜单栏（#45）

- SwiftUI `Window(id: "main")` 持有唯一发布窗口；`NativeMenuBar` 必须接收该窗口，不备用创建另一套编辑器。设置使用独立 Settings scene。
- 打包 `LSUIElement=true`，`applicationWillFinishLaunching` 设置 `.accessory`，不再运行时切回 `.regular`。这会隐藏 Dock 图标，不改变发布窗口的普通排序职责。
- 菜单栏、应用内 Command-0、重新打开应用及通知错误回退统一调用 `showMainWindow()`。点击菜单栏始终唤醒，不按 `isVisible` 切换隐藏。全局快捷键注册尚未实现。
- 主窗口 `.normal`、`hidesOnDeactivate=false`、禁用窗口标签页；`.moveToActiveSpace` 在显式唤起时迁移窗口，`.fullScreenAuxiliary` 请求允许全屏辅助呈现，并禁止参与全屏平铺；其他应用全屏及多显示器效果仍需实测。先将目标窗口排序到前，再激活应用一次；不使用全桌面常驻、浮动层级或循环抢焦点。
- 设置不参与主窗口唤醒。红黄标题栏按钮隐藏主窗口，任务只在首次实际执行时隐藏一次；失焦、Escape、进度和终态没有隐藏监听。
- 历史原型 `inpost-prototype-简约模式.html` 和旧开发计划仅供追溯。当前窗口交互原型为 `inkpost-titlebar.html`，系统桌面与 Dock 行为必须在原生验证。

### 本轮验证（2026-11-09）

- 基线窗口专项 10 项通过；更新后窗口与显隐专项 11 项通过。全量串行 84 tests / 17 suites 通过，真实平台 live 测试未启用。
- `swift build`、release 构建、原型 JavaScript 与打包脚本语法、`git diff --check` 通过。
- 使用 Inkpost 正式签名（身份 SHA-1 `4E15EF1D792EBC692CD2DE06AFC4F242B35D5A99`）打包并验签后替换旧应用；新进程 PID 18320，实际 activationPolicy 为 accessory，包内 `LSUIElement=true`。
- 原生 UI 自动化确认正文获焦与输入、设置只含渠道能力、Command-0 返回主窗口、关闭后恢复保留正文；验收文字已清空。
- ego Lite 原型验证重复唤醒不收起、切换应用不隐藏、关闭后恢复保留正文。网页模拟不作为原生桌面行为证据。
- 系统菜单栏和 Dock 的 UI 自动化读取超时，无法完成实际菜单栏点击及 Dock 视觉检查；跨应用实际遮挡、普通桌面迁移、全屏桌面、多显示器仍待现场验收。窗口配置与单进程排序测试不代表这些场景已通过。

## 验证与维护

### 应用单实例（#46）

- 0.14.4 提交复核：最终代码全量串行 100 tests / 19 suites 通过（129.361 秒）；compact-smoke、打包脚本语法、停止脚本类型检查及 `git diff --check` 通过。正式签名分阶段替换与启动、重复直接启动交接、单进程检查通过；DMG 完整性、ZIP 解压验签、版本及 SHA256 校验通过。

- `ApplicationStartup` 在 SwiftUI `App.main` 之前获取 `~/Library/Application Support/Inkpost/Runtime/instance.lock` 的非阻塞独占 `flock`；锁由内核随进程退出释放，锁文件不删除，旧 PID 或残留文件不能冒充占用。`O_CLOEXEC` 避免浏览器等子进程继承租约，`O_NOFOLLOW` 拒绝锁文件软链接。
- LaunchServices 仍处理常规重新打开；文件锁补足直接二进制、并发和不同应用副本的启动。后启动进程通过当前锁所有者的随机身份发送本地分布式通知，已有实例沿用 `showMainWindow()`；窗口就绪且确实可见后才确认交接。超时不接管、不终止旧任务，错误写入 stderr 并交由系统提示辅助进程展示，失败的重复启动本身退出，不驻留第二套应用。
- `make-app.sh` 在独立目录构建应用包、正式签名并验签，通过后先由 `stop-app.swift` 按 bundle identifier 有序退出各路径的旧应用，再以新二进制 `--stop-running-instance` 等待锁所有者退出（覆盖无 bundle 的直接运行）。旧包移入 `.build/inkpost-previous.*/` 保留，再安装并启动新包；构建／签名失败不覆盖旧文件、不停止旧进程。拒绝退出或超时即停止替换，不按进程名称批量杀进程。普通启动不使用停止参数。
- 单实例互斥适用于包含该启动保护的新版本副本；无法让未经更新的历史二进制在未来直接启动时自行遵循新锁。升级打包流程会先退出当前可识别的旧应用，新验证统一使用更新后的签名副本。

#### 验证记录（2026-11-10）

- 全量串行 100 tests / 19 suites 通过；最后的等待请求清理调整后，7 项单实例专项复测通过。覆盖独占锁、旧元数据、子进程异常退出、启动就绪前唤起、真实主窗口及内容／图片／渠道／任务身份保留、无响应超时、窗口未显示不确认成功，以及等待实际退出后替换。真实平台 live 测试未启用。
- `swift build` 对应 release 构建、打包脚本语法、停止脚本类型检查及 `git diff --check` 通过。最初默认构建缓存仍包含旧项目路径 `publishflow`，改用 `.build/issue46` 验证；没有删除或篡改其他构建缓存。
- 正式签名原包与副本同时直接启动 10 次，后来进程全部退出码 0，普通打开和 `open -n` 不留下第二个实例。模拟旧实例 SIGKILL 后，8 次冷启动竞争只留下一个新所有者；锁文件保留也能恢复。实际 SIGSTOP 模拟无响应时，重复启动返回 1 并输出具体错误，原实例和身份不变，随后恢复原实例。系统提示辅助弹窗未单独做视觉验收。
- CUA 确认验收标题、多行含空白／emoji 正文、测试图片和渠道选择在重复启动后保留；最终验收文字与图片已清理，渠道恢复为原有五项选择。真实在途渠道操作没有执行，其任务状态保持由自动化覆盖。当前桌面、全屏和多显示器行为沿用 #45，本项未新增现场覆盖。
- 故意使用不存在的签名身份时，旧应用 PID 65496、锁身份及应用二进制 SHA-256 均不变，旧包验签仍通过。随后正式签名的分阶段替换通过，旧包保存在 `.build/inkpost-previous.i7sI7E/Inkpost-Compact.app`。
- 最终正式身份为 Inkpost（SHA-1 `4E15EF1D792EBC692CD2DE06AFC4F242B35D5A99`）；`.build/Inkpost-Compact.app` strict/deep 验签通过，新 PID 68376。该最终包及副本再次 10 次并发启动和 `open -n` 通过，进程检查只剩该新实例。也验证过直接运行的无 bundle 旧实例可被打包流程退出并替换。

### 图片排序（#11，2026-11-10）

- 根因：`moveAsset(_:before:)` 删除源图片后仍使用删除前的目标索引；例如 `[A,B,C]` 中 A 放到 C 前曾变为 `[B,C,A]`。现按删除造成的索引位移插入，目标前缘显示插入线；自身落点和失效路径不改顺序。
- 原生排查还确认 AppKit 起拖搭配 SwiftUI 落点的版本无法完成排序，用户手动复核也失败。最终由同一个 AppKit 视图注册私有 pasteboard 类型并处理拖动源、目标进入/离开、落下和会话结束；目标直接读取本次原生拖动数据，校验当前可编辑状态与素材存在性，不依赖 SwiftUI 异步更新的 dragging 值。外部来源拒绝，未新增外部图片拖入能力。
- 会话结束清除拖动视觉状态；原生覆盖层同步悬停，并将右上角点击转交现有移除动作，其余点击仍打开预览。任务禁用时清理高亮，控制器再次校验状态。私有类型避免误落正文时写入路径。
- 基线 84 tests / 17 suites 通过；最终 93 tests / 18 suites 串行通过，含九组落点、无效/禁用操作、重复排序、原生源/目标回调、移除点击及完整素材经过实际 DispatchService 抵达记录适配器的覆盖。真实平台 live 测试未启用。
- release 构建、`git diff --check` 通过。最终验收包 `.build/issue11-final/Inkpost.app` 使用 Inkpost 正式身份 `4E15EF1D792EBC692CD2DE06AFC4F242B35D5A99` 签名并通过 strict/deep 验签，已启动 PID 50944。替换前确认旧窗口没有用户内容，仅本轮测试图片。
- 原生 UI 实测：红/绿/蓝中红放蓝前得到绿/红/蓝；蓝移到首位得到蓝/绿/红；相邻向后保持原顺序，相邻向前正确交换；自身落点不变；误放正文后 Escape 取消恢复透明度、不插入路径，之后再次排序成功；预览打开/关闭及移除指定图片正确，其余图片不变。最终包复核排序、移除、自身落点和取消通过，验收图片已全部移除，标题/正文均为空。
- 执行中禁用、失效素材与外部来源拒绝由自动化测试覆盖，未在真实渠道任务中另做交互验证；窗口外释放未单独实测。

- 0.14.3 提交复核：93 tests / 18 suites 串行通过（126.357 秒）；本地 compact-smoke、打包脚本语法、`git diff --check`、正式签名 release 构建与启动检查通过；DMG 完整性、ZIP 解压后 strict/deep 验签及 SHA256 校验通过。

- 使用内置 Swift Testing，按改动影响运行现有测试；服务依赖可注入，协调测试不依赖真实浏览器或密钥。
- 代码变更验证 `swift build`、`swift test`；涉及浏览器流程且 ego Lite 可用时运行本地 fixture 冒烟，不在真实平台发布。
- CLT-only 环境使用以下测试参数补充 Testing framework 和关闭 cross-import overlays（AppKit/剪贴板测试串行运行）：

```sh
swift test --no-parallel \
  -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
  -Xlinker -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks
```

- 改渠道前阅读对应的 `Sources/PublishKit/Services/Channels/*ChannelAdapter.md`，改动后同步维护；根文档不重复渠道细节。
- 保留完整请求交付、校验、成功、等待人工、结构化失败与恢复、取消和过期结果拒绝的契约覆盖；渠道行为通过真实适配器验证，避免只测替身服务。
- 验证实际后置条件，不能把已发出操作当作成功；不把提示词限制声称为可强制执行的安全边界。

## 异常结果展示与导航（#47，2026-11-10）

- 0.15.0 提交复核：106 tests / 21 suites 串行通过（130.178 秒）；启用本地 ego fixture 的导航专项 1 test / 1 suite 通过（4.124 秒），覆盖原 Page 激活、缺失反馈和工作区打开。compact-smoke、原型 JavaScript 与打包脚本语法、差异检查、正式签名 release 构建与启动通过；DMG 完整性、ZIP 解压验签、版本及 SHA256 校验通过。正式应用内结果按钮到浏览器的完整点击链路尚未验收，#47 保持开启。

- 主窗口结果区复用 DispatchAction/DispatchStatus，仅保留一个前往按钮和静态汇总；不再呈现渠道错误卡、重试入口、修改未完成内容入口及执行日志。内部事件、结构化错误与诊断日志继续保留。
- DispatchController 按任务顺序选择第一个未完成渠道；DispatchService 定位已有 Space/Page，以 `Page.bringToFront` 激活后交还控制权，不执行编辑或创建页面。缺失 Page 显示简短提示，同一按钮切换为打开工作区；其他导航错误保留重试入口。导航期间阻止重复点击、恢复及重置。
- 已填好任务沿用成功交接后归档和清空编辑器的既有行为；异常导航不改变渠道结果或清空稿件。本项没有重新设计恢复自动填写与动效生命周期。
- 全量串行测试 106 tests / 21 suites 通过（129.705 秒）；专项 34 tests / 3 suites 通过，包含真实 ego 本地 fixture 页面切换、关闭目标 Page 后的缺失报告和工作区入口，不涉及真实社媒发布。原生 NSHostingView 对失败、已填好、取消三种状态的尺寸与截图检查通过；真实平台 live 测试未启用。
- release 构建通过；正式身份 Inkpost（SHA-1 `4E15EF1D792EBC692CD2DE06AFC4F242B35D5A99`）strict/deep 验签通过，新应用 `.build/Inkpost-Compact.app` 已启动，检查时 PID 21516。旧包由项目打包脚本保留在 `.build/inkpost-previous.IaPtoV/Inkpost-Compact.app`。未在正式应用中运行真实渠道任务，不能将分层验证视为真实社媒全流程验收。
- 默认旧构建缓存带有历史项目路径，测试和构建分别使用 `.build/issue47-tests`、`.build/issue47-release`，未清除其他缓存。

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

- 0.14.2 提交复核：swift build、84 项串行测试（17 个套件）、compact-smoke、两个原型 JavaScript 与打包脚本语法、签名 release 构建及启动、DMG/ZIP 完整性与解压签名通过；新版主窗口正常响应且正文获焦。跨桌面、全屏、多显示器及系统菜单栏/Dock 视觉检查仍待现场验收。
