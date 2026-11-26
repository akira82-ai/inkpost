# 开发参考资料

## ego 激活确认（#68，2026-11-21）

- CLI 定位同时检查绝对 PATH 项、用户 `~/.local/bin`、Homebrew 常用目录，兼容 Finder／Sparkle 启动时仅有系统 PATH 的环境；显式绝对 PATH 保持优先，忽略相对和空目录，缺失命令仍明确报错。新增四项路径解析测试。

- 用户截图为“未能激活 ego，内容已保留，请重试”；该文案来自最终交接或通知导航，不是渠道正文校验。现场运行 `/Applications/Inkpost.app` 0.23.0。系统日志能看到激活请求及墨驿窗口切换，但原代码未保存此次导航的具体错误，因此尚未确认用户现场的唯一根因。
- `EgoWorkspaceNavigator.activate` 原先在 LaunchServices 打开请求返回后立即检查 `isActive` 与前台 PID；现在对同一次请求进行最多 40 次、间隔 50ms 的状态观察，确认后才成功。超时、目标退出及取消均明确失败，不反复激活或吞错。新增 `ego-navigation` 系统日志记录请求、确认或失败时的 PID，不记录稿件或网页内容。
- 49 项导航、控制器和恢复回归通过，覆盖模拟延迟成功、超时及目标退出。独立编译运行生产激活函数已确认当前 ego 成为前台；首次独立探针也正常，未复现用户完整现场，不将本次保护修复宣称为已验证解决所有无法发布问题。测试日志 `/tmp/inkpost68-tests-local.log`。
- release 构建及正式 Inkpost 签名 strict/deep 验证通过，独立包 `.build/Inkpost-issue68.app`，构建日志 `/tmp/inkpost68-build.log`。未停止、替换或重启运行中的墨驿，未重试用户任务、修改页面或触发平台最终发布。用户现场稿件与任务保持原状，修复后的真实墨驿交接仍需后续现场验证。

- 0.23.1 交付复核：完整串行回归 158 tests / 28 suites 通过（226.768 秒，`/tmp/inkpost-0231-tests.log`）；release 构建、正式签名、DMG 完整性、ZIP 解压验签、版本、SHA256、签名 appcast、脚本语法及差异检查通过。仅打包交付，不停止、安装或启动本机新版，#68 保持开启待现场复验。

## 自动更新退出交接修复（#66，2026-11-21）

- 用户现场 0.21.2 → 0.22.0 卡在安装重启。系统日志于 10:40:00 和 10:40:12 确认收到 Sparkle 的 quit AppleEvent，但 AppKit 报 `App termination blocked by modal sheet`。更新包 EdDSA 校验通过，现场旧进程仍运行；不是已确认的签名失败或单进程锁问题。
- 重启操作先隐藏更新 sheet，等待 SwiftUI `onDismiss`；若原生窗口仍有 attached sheet，则继续等待 `NSWindow.didEndSheetNotification`，之后重新检查任务/稿件安全，才调用 Sparkle 安装或重试退出回调。不使用固定动画延迟，不强杀进程。
- 更新面板只在存在可执行回调时允许重启/重试退出，错误或会话结束会取消待交接动作及通知监听。系统日志增加准备就绪、面板关闭、安装回调和退出安全判断，不记录稿件内容。
- 隔离正式签名回归：`INKPOST_BUILD_PATH=.build/issue66-update` 运行 `Scripts/test-update.sh`，使用独立 bundle ID 和锁；真实 SwiftUI sheet 打开后点击重启，确认原生 sheet 移除、旧进程退出、1.0 → 2.0 安装重启和单实例；篡改 ZIP 与签名清单均被拒绝。证据目录 `/tmp/inkpost-update-test.FnENoC/`（各场景日志在对应子目录的 `events.txt`）。更新专项 12 项通过，包括原生 sheet 移除前不能安装、重复点击、退出前重新检查稿件、失败取消待执行动作及退出保护。未重触发用户现场安装，未替换本机墨驿。

- 0.22.1 提交复核：完整串行回归 151 tests / 27 suites 通过（227.554 秒，`/tmp/inkpost-0221-tests.log`）；正式签名 release 构建、strict/deep 验签、DMG 完整性、ZIP 解压验签、版本、SHA256、签名 appcast、脚本语法与差异检查通过。仅打包交付，不安装、替换或启动本机墨驿；用户原现场升级仍待复验，#66 保持开启。

以下内容从 AGENTS.md 移出，保留为既有技术方案与操作参考，不作为新需求的约束，也不代表这些方案必须继续沿用。涉及变更时以用户确认的需求、当前代码和实际验证结果为准。

## 发布版本号

- **Patch**：修复已有能力，例如修正渠道图片排序或在线更新失败（`0.18.0 → 0.18.1`）。
- **Minor**：新增向后兼容的用户能力，例如新增可用渠道，或已有渠道首次支持一种内容类型（`0.18.0 → 0.19.0`）。渠道以用户能在正式应用中选到并完成该渠道承诺的操作为准；只有适配器、尚未开放入口时，不单独升 minor。
- **破坏兼容性**：在 `0.x` 阶段升 minor，在 Release 开头说明受影响范围和迁移办法；进入 `1.x` 后升 major。`1.0.0` 留到项目准备公开承诺兼容性时发布。
- 纯内部重构、测试、格式、注释或维护文档不单独升版本；同一次发布包含多类改动时，按影响最大的类别升一次。

## 代码组织

### 正文视觉折行（#54，2026-11-11）

- `PasteEditor` 的原生编辑器初始 frame 使用 `NSScrollView.contentSize`，不再写死 384pt。滚动区域初始宽度为 0 时，原有固定宽度会被 autoresizing 保留为额外偏移，使文本在可见宽度之外才折行。继续使用系统 NSTextView 宽度跟随和段落布局，不对字符串插入换行。
- 原生 NSHostingView/NSWindow 隔离验证通过：实际生产编辑控件粘贴中文、emoji、长英文与长链接，依次切换 300/480/240pt 可用宽度，检查编辑器与视口宽度一致、布局不横向溢出、行高随宽度变化，复制及模型文本保留手工换行、空行和空格，继续编辑正常。`ImagePasteTests` 5 项通过（0.182 秒），原有图片粘贴和焦点回归包含其中；日志 `/tmp/inkpost54-tests.log`。
- release 验证包 `.build/Inkpost-issue54.app` 使用正式 Inkpost 身份 `4E15EF1D792EBC692CD2DE06AFC4F242B35D5A99` 构建，strict/deep 验签通过；日志 `/tmp/inkpost54-build.log`。当前正式应用有用户正文和三张图片，未停止或替换运行进程，未将旧进程作为新版本验收；实际正式窗口现场验证仍待用户稿件处理后进行。
- 用户随后授权启动：通过项目脚本正式签名验签后停止旧进程、替换并启动 `.build/Inkpost-Compact.app`，旧包保留在 `.build/inkpost-previous.MtYvG8/Inkpost-Compact.app`，日志 `/tmp/inkpost54-launch.log`。启动前保留当时的 117 字正文与两张图片，启动后已按原顺序恢复，六个渠道选择不变；CUA 截图确认正式窗口正文在可见宽度内折行。未点击发布。

- 0.19.1 提交复核：全量串行 132 tests / 24 suites 通过（185.252 秒）；差异和打包脚本语法检查通过。正式签名 release 构建、DMG 完整性、ZIP 解压验签、版本、SHA256 和签名更新清单校验通过。本轮仅打包，未替换运行应用，未重新操作真实平台。

### 全局快捷键（#37，2026-11-11）

- `AppLifecycle` 持有一个 `ShortcutController`，主窗口安装完后开始注册，应用退出时停止。按键释放调用 `NativeMenuBar.toggleMainWindow()`，前台主窗口收起，其余状态复用 `showMainWindow()` 唤醒；不依赖分发服务或渠道适配器，仅编辑状态重新唤起时请求正文焦点。
- 设置复用 KeyboardShortcuts 的 binding 录入控件，不启用库的全局监听。`GlobalHotKey` 用系统 `RegisterEventHotKey`/`UnregisterEventHotKey` 完成实际注册并暴露 OSStatus 错误；不使用事件截取或权限弹窗。录入期间根据库的录入通知暂停自有注册，避免原组合键被系统消费；该通知是固定版本的内部协议，升级必须复核录入与取消测试。
- 配置以 `KeyboardShortcuts.Shortcut?` JSON 保存于 `Inkpost.wakeShortcut`，明确保存的 null 表示停用，缺少配置才采用默认键。损坏配置提示重新设置，不静默恢复默认键；注册失败保持设置并提示，不伪报已启用。
- 第三方来源：`https://github.com/sindresorhus/KeyboardShortcuts`，版本 3.1.0，提交 `772133d9dbe800fdac0473226822994c5c162c58`，MIT 许可证。在 `Vendor/KeyboardShortcuts` 保留构建所需源码、语言资源与 license；应用包同时附带许可证及资源 bundle。
- 采用本地依赖的原因：CLT 6.2.3 缺少 SwiftUIMacros 和 PreviewsMacros。仅在 `ConflictPolicy.swift` 将 `@Entry` 等价展开为 EnvironmentKey，`Recorder.swift` 的三个 Xcode 预览放在 `INKPOST_XCODE_PREVIEWS` 条件中；依赖清单移除未随库引入的上游测试目标。未改变录入器产品行为。升级时与上述上游提交比较这三处差异，不能直接改 `.build/checkouts`。
- 方案选择：复用成熟录入与校验，保留少量可观测的系统注册衔接，避免重复实现录入器，也避免把库内部未公开的注册结果当成成功。默认组合键由用户确认，不采用库“不预设组合键”的产品建议。
- 验证：快捷键与窗口专项 14 tests / 2 suites 通过；最终完整串行回归 130 tests / 24 suites 通过（187.798 秒），真实平台 live 测试未启用。覆盖默认键、修改/显式停用及恢复配置、损坏配置、注册失败/重试、录入暂停与恢复、真实 Carbon 重复注册失败及解绑释放、六种任务阶段保留原窗口/原稿/任务。
- 正式 Inkpost 身份 `4E15EF1D792EBC692CD2DE06AFC4F242B35D5A99` release 构建、strict/deep 验签和脚本替换启动通过；旧包保留在 `.build/inkpost-previous.2ydDZT/Inkpost-Compact.app`。原生自动化确认设置显示默认 `⌘'` 和已启用，实际录入 `⌃⌥⌘M`、清除停用、恢复默认键成功；访达窗口前台触发默认键后，系统前台身份从 `com.apple.finder` 变为 `com.publishflow.app`，测试标题仍在且正文获焦。测试稿已清空，渠道选择未改动，未填写或发布真实社媒内容。
- 未现场覆盖跨桌面、全屏、多显示器、真实在途渠道任务和系统权限全新账户；任务状态保留以自动化测试为证据，窗口跨桌面沿用既有入口，不将配置值当作现场验收。测试日志 `/tmp/inkpost37-tests.log`、`/tmp/inkpost37-regression.log`，构建日志 `/tmp/inkpost37-build.log`。初次沙箱测试被 Swift 缓存写入权限阻止；直接上游依赖构建暴露 CLT 缺少宏插件，已按上述方式适配并重新验证。
- 后续用户修正为显示／隐藏切换：新增 `toggleMainWindow()`，以当前桌面、应用激活且主窗口为 key window 判断前台；满足时复用收起，否则复用唤醒。专项复测 15 tests / 2 suites 通过（3.075 秒），包含遮挡窗口应唤醒、六种任务阶段切换不改变任务和内容。正式签名 release 构建及替换启动通过，旧包保留在 `.build/inkpost-previous.5GLJ1A/Inkpost-Compact.app`，运行 PID 98777。日志 `/tmp/inkpost37-toggle-tests.log`、`/tmp/inkpost37-toggle-build.log`。该修正版未重跑前述全量测试；原生自动化未能稳定保持目标窗口在前台，未确认真实连续按键的隐藏／再显示效果，不将本次输入尝试记为通过。

- 0.19.0 提交复核：切换行为修正版全量串行 131 tests / 24 suites 通过（186.326 秒）；差异及打包脚本语法检查通过。正式签名 release 构建、DMG 完整性、ZIP 解压验签、快捷键许可证与资源 bundle、版本、SHA256 和签名更新清单校验通过。仅打包，未替换运行应用；上述原生现场验收边界仍保留。

### 分发输入首尾空白（#51，2026-11-11）

- `DispatchController.dispatch()` 创建共享任务快照时，对整段标题和正文各调用一次 `trimmingCharacters(in: .whitespacesAndNewlines)`；不逐行处理，不修改编辑状态。各渠道及登录恢复复用该快照，HTML 和有序素材不变。
- 正文纯空白沿用 `PlatformRules.canStart` 的必填校验，在创建任务前阻止；标题纯空白成为空标题，仍按各渠道的标题规则校验。适配器继续按收到的请求完整核对内容，不额外放宽校验。
- 验证：修改前后公共分发测试均为 38 tests / 1 suite 通过；`swift build` 和全量串行测试 124 tests / 23 suites 通过（186.236 秒）。覆盖首尾空格、制表符、CRLF、内部空行/缩进/标签/emoji、原稿保留、空白标题/正文及恢复快照。真实平台 live 测试未启用，未重新启动运行中的应用。

- 0.18.1 提交复核：124 tests / 23 suites 串行通过（185.179 秒）；差异与打包脚本语法检查通过。正式签名 release 构建、DMG 完整性、ZIP 解压验签、版本与 SHA256 校验及签名更新清单校验通过。本次仅打包，未替换运行中的应用，未重新进行真实平台交互验收。

### 在线更新（#49，2026-11-10）

- 精确依赖 Sparkle 2.10.1，SPM 锁定 revision 和官方二进制校验。`UpdateModel` 存展示状态，`UpdateController` 适配官方 `SPUUserDriver`/`SPUUpdaterDelegate`，SwiftUI 视图呈现更新面板与设置；框架负责调度、下载、版本判断、验证和独立安装重启。不另建下载器、安装进程或轮询检查计时器。
- `Scripts/update-config.plist` 为唯一更新配置来源，打包合并到 Info.plist。生产代码要求 HTTPS 与 32 字节 Ed25519 公钥，清单和归档都必须签名；清单验证失败不降级，归档在解压前验证。远端说明按不可执行纯文本显示，不加载远端 HTML/JavaScript。
- 更新源为 `https://github.com/akira82-ai/inkpost/releases/latest/download/appcast.xml`。清单内更新包指向具体 `v版本` Release，不能把 latest 链接当归档地址。0.17.0 起 Release 配套发布签名清单与更新包。首个包含更新器的版本须先手工安装，历史无更新器版本无法自行启动这条升级链路。
- 签名私钥保存在 macOS 登录钥匙串，专用账户 `com.publishflow.app.sparkle`；源码仅保存公钥。必须安全备份私钥并限制发布签名权限；不要提交、打印或向日志导出私钥。当前代码签名为 Inkpost 自签名（SHA-1 `4E15EF1D792EBC692CD2DE06AFC4F242B35D5A99`），未做 Developer ID 公证；用于公开分发前仍须配置相应身份与公证流程，不能把本地验签等同于 Gatekeeper 公证通过。
- `make-app.sh` 在签名之前嵌入框架，保留 symlink；辅助应用、Autoupdate、XPC、框架、主应用按由内向外正式签名，最后 strict/deep 验证。`INKPOST_APP_VERSION`/`INKPOST_BUILD_VERSION` 可指定版本；后者决定 Sparkle 的版本排序，必须比已发布版本增大。`INKPOST_PACK_ONLY=1` 只生成新路径，不停止或替换当前应用。
- 本地准备示例（路径和版本替换为本次实际发布值；只生成文件，不上传）：

```sh
INKPOST_SIGNING_IDENTITY=正式身份 INKPOST_BUILD_PATH=.build/compact \
  INKPOST_PACK_ONLY=1 INKPOST_APP_OUTPUT=.build/Inkpost-Release.app \
  INKPOST_APP_VERSION=新版本 INKPOST_BUILD_VERSION=新构建号 \
  Scripts/make-app.sh release
Scripts/prepare-update.sh .build/Inkpost-Release.app /新的产物目录 /更新说明.txt
```

- 准备脚本校验应用签名、公钥与钥匙串匹配，生成仅含 `.app` 的 ZIP、嵌入说明的签名 appcast.xml 及 SHA256SUMS.txt；实际 CPU 架构写入归档名。正式 Release 需一起上传该清单和匹配归档，资产名不得更改，不得修改已签名清单或 ZIP；变更后重新生成并签名。必须先确认对应版本的发布，不能把本地验收包直接上传冒充正式版本。
- 单元及回归：113 项既有基线通过，新增 7 项更新专项通过，完整 120 tests / 22 suites 通过（128.095 秒）。覆盖在途任务／所有内存内容阻止重启、下载后新增稿件再次保护、取消仅调用一次、收起不取消、不将下载当安装成功、无新版与失败分离、安装等待时退出保护及原生视图尺寸。
- 真实隔离升级可重跑：`INKPOST_SIGNING_IDENTITY=正式身份 INKPOST_BUILD_PATH=.build/issue49 Scripts/test-update.sh`。需登录钥匙串内已有专用签名密钥；只在本机随机端口开 HTTP，生产代码不允许此例外。使用生产 UI 适配器和生产单实例锁，创建唯一测试 bundle ID/锁目录，不操作真实墨驿或发布外部内容。旧版 1.0 退出后新版 2.0 取得同一锁；篡改归档和篡改清单均被框架拒绝，旧包版本与签名保留。三种场景已通过，记录 `/tmp/inkpost49-repeatable-integration.log`，产物 `/tmp/inkpost-update-test.t7x2s2`。
- 测试 fixture 仅验证隔离应用的辅助进程安装链路；不能替代 GitHub Release 实际分发、全新机器 Gatekeeper、公证或所有磁盘权限失败场景验收。
- 最终复核：新增后台检查不弹面板、发现后等待显式下载的隔离验收也通过；三场景重跑日志 `/tmp/inkpost49-repeatable-final.log`，证据目录 `/tmp/inkpost-update-test.sOaCMr`。最后的 Escape 操作调整后，7 项更新专项复测通过。release 构建、正式签名 strict/deep 验证、本地生成签名清单与归档、脚本语法及差异检查通过。
- 标题栏还原修正：齿轮和更新提示由同一个右侧附件承载，齿轮保持原右边距，绿色圆点／细边框提示只向左展开，下载显示百分比；没有提示时附件恢复为原齿轮宽度。16 项更新与窗口专项通过，原生坐标测试覆盖提示出现、下载进度、准备完成和消失，不移动齿轮，设置点击保持原行为。一次并行进行 CUA 操作干扰了窗口前后排序断言，停止界面操作后独立重跑通过，日志 `/tmp/inkpost49-titlebar-final2.log`。正式签名 release 构建验签及替换启动通过，CUA 确认无提示时齿轮位于右侧且无额外占位；有更新各阶段由原生窗口回归测试覆盖。旧包保存在 `.build/inkpost-previous.Z0zCYM/Inkpost-Compact.app`。
- 已启动正式签名的新构建 `.build/Inkpost-Compact.app`（检查时 PID 93964），旧包保存在 `.build/inkpost-previous.OgqjIB/Inkpost-Compact.app`。CUA 确认设置展示当前版本、自动检查开关和手动检查入口，未发布源的实际检查显示失败，可按 Escape 收起并返回正文；未改用户内容。原型已同步显式重启步骤，ego Lite 验证下载／校验后停在准备就绪，再点击才模拟新版，不自动显示成功。上述为 0.16.0 实现阶段的验证记录。

- 0.17.0 交付复核：最终全量串行 121 tests / 22 suites 通过（129.331 秒）；隔离真实升级三场景通过（正常安装重启及单实例、篡改归档拒绝、篡改清单拒绝），日志 `/tmp/inkpost-0170-integration.log`。正式签名 release 构建、嵌套框架验签及启动、compact-smoke、脚本/plist/原型语法与差异检查通过；生成签名 appcast.xml 和匹配归档，DMG 完整性、ZIP 解压验签、0.17.0 版本与 SHA256 校验通过。首次含更新器的正式版本仍需手工安装。

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
- 菜单栏、应用内 Command-0、重新打开应用及通知错误回退统一调用 `showMainWindow()`。点击菜单栏始终唤醒，不按 `isVisible` 切换隐藏。全局快捷键的切换行为见 #37 小节。
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

## 渠道状态、登录恢复与任务交接（#48，2026-11-10）

- 沿用 DispatchModel、DispatchController、DispatchService；等待登录为中间态，仅恢复本轮等待渠道，沿用输入快照和原 Page，已填好渠道不重复。视图以无背景状态图标呈现填写中、已填好、需登录、其他问题；登录/问题图标独立可点击，提供悬停和无障碍说明。
- ego 控制权以 Space 为单位。自动操作期间的渠道导航排队，待本轮其余渠道执行结束后打开；等待登录 handOff，所有自动操作终止后 finish 并保留 Pages。完成后按捕获的原 URL 唯一定位渠道 Page；URL 变化、重复或缺失时报错，不跳到猜测页面。
- 最终主按钮打开任务 Space，成功后归档并清空标题、正文、图片，保留渠道选择；异常、跳过、取消均适用，导航失败保留稿件。渠道图标导航不重置，通知导航不清空其他任务。收尾、导航、继续互斥，取消后仍执行交还。
- 基线 106 tests / 21 suites 通过；最终完整串行回归 111 tests / 21 suites 通过（128.474 秒）。覆盖批量登录恢复、成功渠道不重做、跳过、取消、收尾失败、导航排队、重复点击与旧事件隔离。测试日志 `/tmp/inkpost48-verified-tests.log`；本地 compact-smoke 通过，无真实发布。
- 本地 ego fixture 验证原 Page 切换、缺失反馈、完成后 user ownership、重开渠道与 Space；原生 NSHostingView 覆盖等待登录等五种任务状态布局。正式应用实测窗口启动、三列渠道、正文中文/空行/emoji 粘贴，验收文字已清理。
- release 构建与正式身份 Inkpost（SHA-1 `4E15EF1D792EBC692CD2DE06AFC4F242B35D5A99`）strict/deep 验签通过；`.build/Inkpost-Compact.app` 已启动，检查时 PID 44501。旧包保留在 `.build/inkpost-previous.R8fndr/Inkpost-Compact.app`，版本仍为 0.15.0。测试与 release 使用独立 `.build/issue48-*` 缓存。
- 尚未验收真实平台多渠道登录后续填和正式应用最终按钮到浏览器的完整链路；自动化与 fixture 不代表真实社媒全流程通过。上述为实现阶段记录，交付复核见下。

### #48 工作区打开失败后的本地结束入口（2026-11-10）

- 最终导航失败后显示「我已处理，忽略」，与错误提示同排，复用现有清空稿件与 pending 正文聚焦路径。只有已结束任务且最终工作区导航失败才启用；导航、收尾期间不可用，不增加浏览器调用或重建任务。
- 点击清空标题、正文、图片、任务身份、渠道结果和错误提示，保留渠道选择，无二次确认。未点击前继续保留内容与重试能力。
- 最终专项 40 tests / 2 suites 通过（0.471 秒），覆盖三种终态、重复点击、内容/图片清空、渠道选择保留、无新增浏览器操作及执行中/登录等待/交还中的保护；原生截图确认错误文字与按钮同排且窗口高度小于 600pt。没有重新执行真实社媒发布。
- 修复版 release 构建及正式签名验签通过，项目脚本已停止旧应用并启动新版；旧包保留于 `.build/inkpost-previous.xy0uf1/Inkpost-Compact.app`。上述为专项修复阶段记录。

- 0.16.0 交付复核：最终代码全量串行 113 tests / 21 suites 通过（128.407 秒）；真实 ego 本地 fixture 导航专项通过（5.497 秒），验证完成后 user ownership、保留页面及重开渠道与 Space。compact-smoke、原型 JavaScript 与打包脚本语法、差异检查、正式签名 release 构建启动通过；DMG 完整性、ZIP 解压验签、版本与 SHA256 校验通过。真实平台登录续填及正式应用完整跳转链路仍待验收，相关开放 Issue 保持开启。

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

## B站普通图文动态（#29，2026-11-10）

- 新增独立 BilibiliChannelAdapter 和平台注册，复用原有分发、任务快照、PNG 素材、剪贴板租约与收尾逻辑。界面按注册表显示 B站动态，未增加平台专属协调分支。
- 已按真实网页验证点击输入框后原生粘贴、选填标题、正文段落及两张有序 PNG。适配器回读标题、正文和图片状态，同页恢复不重复填写；首次填写前清空旧标题、正文和图片；清空不成功则停止填写，恢复时不重复清空。详见 [适配器维护](../Sources/PublishKit/Services/Channels/BilibiliChannelAdapter.md)。
- B站粘贴会处理首尾空白。真实测试确认原文不一致时抛出 verificationFailed；未通过 trim 弱化校验。标题实际 maxlength=20，按 UTF-16 校验，不截断。未断言未实测的正文、图片上限。
- 专项离线测试通过：原始字段/标题限制，以及 16 种参数化工作流场景。真实 Swift 适配器 liveDynamicWithoutPublishing 通过（16.154 秒），覆盖无标题无图、多段落/空行/emoji、标题加两张测试图、同页恢复、平台处理首尾空白时失败且不重复粘贴。日志 `/tmp/inkpost29-tests.log`、`/tmp/inkpost29-live.log`。
- 测试页仅使用纯色 PNG，测试标题、正文和图片已清理，测试 Space 已 finish；全程没有点击发布。未实测退出登录、登录过期、断网、六图极限、账号限制或正式应用整条分发交接链路；离线故障覆盖不能替代这些现场验收。
- 全量串行回归 124 tests / 23 suites 通过（175.138 秒），日志 `/tmp/inkpost29-regression.log`；测试构建与 `git diff --check` 通过。
- 0.18.0 交付复核：124 项串行测试、23 个套件通过（184.715 秒）；本地 compact-smoke、差异与打包脚本语法检查通过。仅打包模式生成正式签名应用、DMG、ZIP 和签名 appcast；版本、解压签名和 SHA256 校验通过。未替换当前运行的应用。

## #52 当前空间与最终交接（2026-11-11）

- 0.20.0 提交复核：最终代码全量串行 137 tests / 25 suites 通过（185.087 秒）；差异和打包脚本语法检查通过。正式签名 release 构建、DMG 完整性、ZIP 解压验签、版本、自动化用途说明、SHA256 及签名更新清单校验通过。本轮仅打包，未替换运行应用，未重新执行真实浏览器交互；现场验收剩余项保持开放。
- 取代上文历史的每任务新建 Space 和最终精确切换 Space：DispatchService 开始时读取 ego 原生 front window ID / active tab title，使用 listTaskSpaces 的唯一候选及 Browser.getWindowForTarget 精确窗口 ID 校验后 claim 当前空间。重复标题无法唯一确认时显式失败，不试探接管其他空间。
- 每渠道通过 newPage 新建 Tab，EgoBridge 按数字 Space ID 恢复上下文，避免重名空间定位错误；结束使用 finish({keep:"all"}) 保留全部已有和新增页面并交还控制权。Space 0 是合法默认空间，通知与生命周期校验均支持。保留 SDK 任务收尾必需的内部上下文，不主动命名、分组或切换 Space。
- 最终按钮与通知不再调用浏览器导航脚本，只通过 NSWorkspace.openApplication 激活 ego 并检查前台进程；最终成功才归档和重置，失败保留内容及重试。渠道单页入口仍复用已有页面定位能力。
- Info.plist 声明 NSAppleEventsUsageDescription；读取当前窗口可能需要“隐私与安全性 → 自动化”授权，激活 ego 本身不依赖 Apple Events。SDK 无直接 current Space API，此处不猜 ego URL scheme 或私有接口。
- 验证：完整串行回归 137 tests / 25 suites 通过（187.044 秒，`/tmp/inkpost52-full.log`）；最终收尾允许缺失 Space 记录后专项复测 43 tests / 2 suites 通过（0.164 秒，`/tmp/inkpost52-final-tests.log`）。默认 Space 0 的真实导航测试通过（5.646 秒，`/tmp/inkpost52-current-live3.log`）：Space 数量不变、两个渠道各新增一个本地 fixture Tab、原有 target ID 全部保留、完成后 user ownership、激活 ego 成功；随后只清理唯一标记测试 Tab，没有发布内容。
- 正式 Inkpost 签名 debug 包 `.build/Inkpost-issue52-current-space.app` 已构建，strict/deep 验签通过（`/tmp/inkpost52-build.log`），未停止或替换现有墨驿进程。正式应用首次自动化授权、完整真实渠道分发和多 Space 重名候选现场仍未验收；当前无法唯一确认时显式失败。
- 排查记录：NSAppleScript 在 Swift 并发工作线程执行时，真实测试阻塞在 AppleScript 事件循环；改为主线程执行后只读窗口查询正常。原生脚本只读取窗口身份，不切换窗口；最终唤起使用 NSWorkspace，不依赖该脚本。


## 渠道临时粘贴（#55）

- 文本通过 `ClipboardPasteService.withTextPaste(text)` 写入系统剪贴板，图片通过既有 `ImageClipboardSession.writePNG` 写入；内容和 `org.nspasteboard.TransientType` 在同一个 `NSPasteboardItem` 中一起发布。约定来源：https://nspasteboard.org/ 。不使用敏感信息标记代替临时内容标记。
- 文本适配器随后只发送 ego Lite 原生 `keyboard.press('Meta+V')`，不再调用会重新写入剪贴板的 `keyboard.paste(text)`。保留页面聚焦、既有粘贴流程和回读核验。掘金的直接输入和各渠道文件上传不受影响。
- 获取会话时保存原有条目和各类型数据；任何类型无法读取或读取期间剪贴板变化则停止，避免不完整快照覆盖原内容。成功、失败、取消均通过 defer 尝试恢复，只在 changeCount 仍属于本次操作时执行；新复制内容优先。
- 临时标记是历史工具间的合作约定，不是 macOS 访问控制；无法保证不支持该标记的工具忽略。临时占用期间用户仍可能粘贴到临时内容。用户恰在发送粘贴快捷键期间复制的跨进程竞争也未被此标记消除。
- 先前独立文字/PNG 测试中，用户提供的 echo 截图均未出现测试内容；这是标记过滤的验证，不等同于所有真实渠道已验收。

### 本轮验证（2026-11-11）

- 独立 scratch 构建 `.build/issue55-tests`，按本文 Swift Testing 参数运行全量测试：138 tests / 25 suites 通过（包含 opt-in 真实渠道测试的跳过，不代表这些现场场景通过）。专项覆盖文字/PNG 标记、成功和取消后恢复、多条目/HTML 表示保留、并发租约排他及保留用户新复制内容。
- 临时集成程序链接本轮实际 PublishKit 编译对象，在独立 ego 测试页调用公共服务写入带标记的文字/PNG，再发送原生 `Meta+V`：页面 paste 事件收到完整多行文字及 `image/png` 文件。测试页已结束清理；没有向真实渠道填写或发布。
- 尚未逐渠道进行本轮真实编辑器验收，未打包签名或重启应用，未修改 echo。
- 0.20.1 提交复核：最终全量串行 138 tests / 25 suites 通过（184.954 秒）；差异和打包脚本语法检查通过。正式签名 release 构建、DMG 完整性、ZIP 解压验签、应用与构建版本、SHA256 及签名更新清单校验通过。本轮仅打包，未替换运行应用，未重新进行真实渠道交互验收。
### 窗口唤起连续形变（#53，2026-11-16）

- 0.21.0 提交复核：最终全量串行 143 tests / 26 suites 通过（186.534 秒）；原型脚本、打包脚本语法及差异检查通过。正式签名 release 构建、DMG 完整性、ZIP 解压验签、版本、SHA256 与签名更新清单校验通过；本轮现场验收边界仍按下文记录。
- `NativeMenuBar.showMainWindow()` 接入 `WindowRevealAnimator`；隐藏、最小化或其他桌面唤起时，使用普通层级、不可交互且不进入窗口菜单的临时绘制窗口展示形变。真实主窗口保持最终尺寸、控件和第一响应者，动画完成移除展示窗口，不新增编辑器或业务状态。可见窗口置前不重复播放；重复调用先结束旧动画。
- `WindowRevealView` 参考已确认的 Kokonut UI Morph Popover 原型节奏，使用 AppKit 绘图及系统 Timer：108×38 胶囊右上锚定，420ms 展开，圆角 19→12；内容延迟 120ms 后淡入 200ms。截图按原尺寸裁切，不缩放正文；标题随外壳移动，标题栏背景复用真实截图的空白渐变条。没有引入 Motion/React 依赖或复制其运行时代码。
- 隐藏、移动、失去 key／应用激活和关闭均终止展示；固定窗口的内容尺寸变化重新取样并同步展示区域，不重置动画时钟，不重新排序或激活主窗口。系统减少动态效果直接显示真实窗口，运行中启用同样结束动画；业务自动隐藏后下一计时帧清理展示窗口，不恢复已隐藏主窗口。
- 验证：完整串行回归 141 tests / 26 suites 通过（187.365 秒）；随后新增原生逐帧绘制验收，窗口／快捷键／动效 19 tests / 3 suites 通过（3.774 秒）。最后仅调整标题栏渐变绘制，动效 4 tests / 1 suite 再次通过（1.001 秒），并人工检查胶囊、展开中及完成帧。测试覆盖完成后尺寸／焦点／稿件保留、重复准备、隐藏不复活、失活不抢焦点；减少动态效果路径包含系统设置判断，未修改用户系统设置做现场切换。
- 正式 Inkpost 身份 `4E15EF1D792EBC692CD2DE06AFC4F242B35D5A99` release 构建及 strict/deep 验签通过；项目脚本有序退出旧进程、备份至 `.build/inkpost-previous.er7Kx8/Inkpost-Compact.app`，替换并启动 `/Applications/Inkpost.app`，核对 PID 78117、版本 0.20.1。原生自动化确认最终窗口显示正常、正文获焦；关闭操作后 UI 采集仍显示窗口，不能据此宣称现场收起通过，隐藏／中断结论以专项测试为证据。未现场验收完整动态播放、跨桌面、全屏、多显示器或真实在途任务。
- README 同步新增用户可见动效说明；未升版、提交、推送或更新远端 Issue。日志：`/tmp/inkpost53-regression.log`、`/tmp/inkpost53-final-tests.log`、`/tmp/inkpost53-gradient-tests.log`、`/tmp/inkpost53-installed.log`。初次测试缺少 Testing framework，按本文 CLT 参数重跑通过；初次绘制测试缺少 HostingView 布局尺寸，补上与生产定位等价的最终尺寸后通过。

- 后续修复（同日）：用户反馈点击菜单栏／快捷键看不到动画。正式应用日志复现：SwiftUI 在窗口置前后发送 `NSWindowDidResizeNotification`，旧逻辑在 11ms 终止动画；此前测试只检查最终状态，遗漏了中途持续播放。现改为在内容尺寸调整后重取原尺寸快照并同步绘制窗口，保留原时钟；增加布局后 80ms 仍播放、最终尺寸及透明度恢复的回归测试，并保留 `window-reveal` 分类日志用于区分跳过／正常完成／中断。
- 修复验证：窗口、快捷键及动效专项 20 tests / 3 suites 通过（4.584 秒，`/tmp/inkpost53-resize-tests.log`）。正式签名 release 替换 `/Applications/Inkpost.app`，备份 `.build/inkpost-previous.0fCavI/Inkpost-Compact.app`，PID 83614。原生 UI 操作关闭后使用应用内 `⌘0` 唤起，生产日志确认经历内容尺寸调整且持续 433.956ms 后正常完成，界面与正文焦点恢复；菜单栏与全局快捷键复用同一入口，但本次未单独现场触发这两个入口。构建日志 `/tmp/inkpost53-resize-build.log`。未重新跑无关渠道的全量回归，未提交／推送。

- 图标锚点优化（2026-11-16）：定位以状态栏按钮 cell 的图片区域内「墨」字前 22pt 为锚点，不使用带进度文案的整个按钮中心。图标在屏幕右半边时窗口向左下展开、左半边向右下展开，左右安全边距 12pt；胶囊中心跟随该屏幕坐标，动画结束恰好覆盖真实窗口。受边界限制时钳制胶囊位置以优先完整可见；布局快照更新继续携带同一个屏幕锚点。
- 0.21.1 提交复核：最终全量串行 144 tests / 26 suites 通过（187.440 秒）；差异及打包脚本语法检查通过。正式签名 release 构建、DMG 完整性、ZIP 解压验签、应用与构建版本、SHA256 和签名更新清单通过。真实社交平台及多显示器等现场边界未在本轮重验。
- 验证：窗口／快捷键／动效专项 21 tests / 3 suites 通过（4.412 秒），新增五种左右及边界锚点的起点、过程不越界和最终几何断言。正式 Inkpost 签名 release 构建及安装通过，旧包 `.build/inkpost-previous.U9Mf5t/Inkpost-Compact.app`，新版从 `/Applications/Inkpost.app` 启动；原生 UI 操作唤起后确认画面恢复与正文焦点正常。尚未现场逐项验证多显示器、全屏和菜单栏自动隐藏。日志 `/tmp/inkpost53-anchor-tests.log`、`/tmp/inkpost53-anchor-build.log`。

- 后台唤回修复（2026-11-17）：窗口 `visible=true, focused=false` 时旧判断跳过动画。现后台、非 key 或非当前桌面唤回均重新对齐菜单栏并播放；已在前台不重播，前台快捷键仍收起。README 和产品需求同步。窗口／快捷键／动效 21 tests / 3 suites 通过（4.960 秒），覆盖遮挡后快捷键启动动画、稿件保留与普通层级。正式签名构建及替换启动通过，旧包 `.build/inkpost-previous.Vuuzjx/Inkpost-Compact.app`；原生 UI 确认窗口及正文焦点正常。未现场等待长时间或跨桌面复测。日志 `/tmp/inkpost53-covered-tests.log`、`/tmp/inkpost53-covered-build.log`。未提交／推送。

- 0.21.2 delivery checks: 144 tests / 26 suites passed serially (187.359s). Release build, formal code signature, DMG integrity, extracted ZIP signature, version, SHA256 and signed appcast checks passed. Cross-Space and long-running background scenarios were not revalidated live.

## 单渠道重试（#65）

- `DispatchController.retry` 只接受失败且恢复类型为 `retryAllowed` 的渠道，串行锁定执行，沿用 `draftRequest`，通过公共 `finishTask` 收尾。已完成、需登录、需检查、不可恢复及取消状态不直接触发重新填写。
- `DispatchService.prepareRetry` 在原 Space 重新取得控制，关闭可唯一识别且归属 Agent 的旧页后创建新页；完成后失效的页面标签通过按渠道保存的 URL 唯一匹配，不持久使用 CDP targetId。同 URL 多页、用户改了 URL 或页面归属不明时停止，不猜测关闭。
- 仅替换目标适配器、页面与会话，保留其他渠道结果和公共 PNG 素材；新的 `retry` 命令从头执行，先清空新页面恢复的旧稿并确认清空成功。清空步骤的状态跨登录恢复保留，正文写入结果不确定时不重复清空。关闭成功而新建失败以明确结果允许下次重试；浏览器命令结果未知时交给人工处理。
- 页面脚本边界通过 Node 模拟和 ego 隔离 Space 验证，不以此替代各真实平台的回归验收。

- 知乎、即刻、X、微博复用 `RetryEditorReset`：原生键盘清空正文、原生字段操作清空标题，附件根据已知区域内当前可唯一识别的删除/移除语义控件执行原生点击，并等待数量下降。未知控件或清空结果不符即停止，不猜测点击、不直接修改 DOM。掘金/B站复用已有确定性移除步骤；掘金重试将清空与插入拆开，中间回读验证。页面脚本单元测试需要 PATH 中可用的 Node.js（与 ego 浏览器运行时相同的脚本语言）。

- 0.22.0 交付验证（2026-11-21）：全量串行回归 147 tests / 27 suites 通过（225.881 秒，`/tmp/inkpost-0220-tests.log`）；正式签名 release 构建、strict/deep 验签、DMG 完整性、ZIP 解压验签、版本、SHA256、签名 appcast、脚本语法及差异检查通过。本次仅打包，不安装、替换或启动本机应用；各真实网站重试、附件删除兼容性及正式应用完整交接仍待现场验收，#65 保持开启。

## 菜单栏右键菜单（#67，2026-11-21）

- `NativeMenuBar` 监听左、右键 mouse-up；左键沿用主窗口唤起入口，右键弹出原生 `NSMenu`。菜单顺序为打开、设置、检查更新、分隔线、关于、退出。设置复用 Settings scene，更新复用 UpdateController.show，关于使用系统标准面板，退出调用 NSApp.terminate，沿用现有退出策略。
- `UpdateTitlebarControls` 移除齿轮，只保留现有更新提示。未调整普通退出的任务／稿件策略；当前退出保护仍以 AppLifecycle 现有实现为准。
- 使用独立 `.build/issue67` 缓存完成编译及 NativeMenuBarTests、SoftwareUpdateTests：20 项测试／2 个套件通过。默认缓存存在旧 publishflow 路径的 PCH 冲突，未删除原缓存。菜单实际弹出、关于面板及跨桌面设置窗口视觉仍待现场验收；本轮未安装或启动新版。

- 0.23.0 交付复核：完整串行回归 151 tests / 27 suites 通过（226.446 秒，`/tmp/inkpost-0230-tests.log`）；release 构建、正式代码签名、DMG 完整性、ZIP 解压验签、版本、SHA256、签名 appcast、脚本语法及差异检查通过。本次仅打包交付，不安装、替换或启动本机新版；上述现场验收仍待完成，#67 保持开启。

- #67 参考 Echo：右键临时绑定 NSStatusItem.menu 并由状态按钮触发系统菜单，NSMenuDelegate.menuDidClose 解除绑定；menuWillOpen 刷新更新文案与可用性。此路径仍需正式应用现场验证图标高亮、弹出定位和左右键连续切换。

- 0.23.2 交付复核（2026-11-22）：全量串行回归 159 tests / 28 suites 执行完毕（226.652 秒），仅微博图片 reordered 场景因系统剪贴板被修改而触发所有权保护失败；随后单独复跑完整 WeiboImageTests 六个场景全部通过（25.742 秒），未修改相关代码。其余测试及本轮菜单状态回归通过。日志 `/tmp/inkpost-0232-tests.log`、`/tmp/inkpost-0232-weibo-retest.log`。release 构建、正式签名、DMG 完整性、ZIP 解压验签、版本、SHA256、签名 appcast、脚本语法及差异检查通过。仅打包交付，不安装或启动本机新版；#67 保持开启待现场验收。

## 设置布局与依赖管理（#70）

- ContentView 使用紧凑侧栏与可滚动内容区，复用 ShortcutSettings、SoftwareUpdateSettings；不增加第二套配置存储。
- EgoDependencyController 在设置打开与应用重新激活时检查安装、进程和 CLI 连接，不更改任务归属。EgoDependencyInstaller 使用 ego-browser 官方 macOS 安装脚本的分架构分发地址；发布者 Team ID JGQLC6YQYJ 来自本机正式 ego lite 签名。签名校验与 Gatekeeper 评估通过后才安装到 ~/Applications，不覆盖已有应用。
- AI 配置尚无业务服务，原型中的输入表单未作为可用能力落地。ego Lite 安装链路未在本机实际执行，避免改动现有浏览器环境；不将编译通过作为下载、安装及首次引导已验收的证据。
- 本轮验证：独立 `.build/issue70` 编译通过；设置布局、快捷键、菜单栏和更新专项 29 tests / 4 suites 通过（`/tmp/inkpost70-final-tests.log`）。原生 NSHostingView 渲染截图确认紧凑导航与内容布局，测试检查稿件未修改。未安装或启动新版应用，未执行实际下载安装，未对 AI 能力作已完成声明。

- 0.24.0 交付复核（2026-11-23）：全量串行回归通过（160 tests / 29 suites，227.143 秒），设置测试保留尺寸与稿件断言，移除固定路径截图输出。Release 构建、代码签名、DMG 完整性、ZIP 解压验签、版本、SHA256、自动更新清单签名及脚本语法检查通过。ego Lite 下载、实际安装、首次引导及键盘焦点交互待现场验收，#70 保持开启。

## Bonjour 适配器（#71，2026-11-25）

- 新增 BonjourChannelAdapter，通过 ChannelAdapter/ChannelRegistry 接入；PlatformID 增加 bonjour，现有渠道列表自动展示。未修改公共分发、素材和剪贴板实现。
- 维护说明见 [Bonjour adapter maintenance](../Sources/PublishKit/Services/Channels/BonjourChannelAdapter.md)。正文和有序 PNG 均使用公共剪贴板服务；保留用户新复制内容、原始请求与已有不同草稿，支持登录恢复、重试清理、取消及不明确写入结果的防重复保护。
- ego Lite 真实页面核实：主页发帖弹窗自动聚焦 textarea，maxlength=5000；同一导航内存在隐藏的重复发帖按钮，使用排除 aria-hidden 的 XPath 定位。图片原生粘贴可保持同源 blob 预览，状态为 loaded；不以 CDN URL 作为唯一就绪条件，不将本地预览就绪声称为服务器上传完成。未自动选择分区或点击发布。
- 独立构建目录 /tmp/inkpost-bonjour-build 编译通过；Bonjour 专项 4 tests / 2 suites 通过（57.228 秒），含 10 种正文/恢复场景、6 种图片检查场景，以及真实页面两张图片、带空白和空行正文的填写、重试清理与恢复校验。测试 Space 已结束，未发布帖子。
- 当前未验证正式应用内从渠道选择到完成交接的完整点击链路，也未验证真实站点未登录流程；未安装或启动新版应用。
- 回归执行覆盖 163 tests / 31 suites（272.445 秒），唯一失败为结果布局测试仍按原六渠道限定 600pt 高度；新增第七渠道产生一行 36pt 单元格及 8pt 间距，按实际渠道行数调整测试上限，未修改正式界面。最终 Bonjour、结果布局和素材取消专项 7 tests / 4 suites 全部通过（47.481 秒）。首次中止轮次未完成的素材取消测试，单独复验通过，不作为已确认挂起问题。差异检查通过；未声称最终版本一次完整全量运行全部通过。

- 0.25.0 交付复核：全量串行回归通过（164 tests / 31 suites，274.217 秒）。正式签名、DMG、ZIP、版本与更新清单校验通过。

## 每次填写前清空目标编辑器（#73，2026-11-25）

- 根因证据：Bonjour 原在线测试写入固定正文与两张 80×80 蓝/橙图片，但结束后未清理网站草稿。新建 Page 点击「发帖」仍恢复同一正文和两图；页面存在 `bonjour:community-editor-draft:create` 持久草稿。正式适配器没有这些固定输入，原实现遇到不同草稿会停止，不代表它把本次任务输入替换为测试数据。
- 用户最新确认：所有适配器每次执行填写（prepare、retry、resumeAfterUser）均先清空目标标题（如有）、正文和附件，确认清空后完整填写原任务快照。知乎、即刻、X、微博复用现有原生清空服务；掘金、B站、Bonjour沿用各自清空控件；本地 fixture 同样执行并核对清空。只有清空成功才重置图片与文字检查点；失败不继续粘贴。未修改公共调度或任务输入快照。
- Bonjour 在线自动测试改为只读编辑器结构检查，不再写测试稿或测试图；隔离测试覆盖恢复出的旧稿、旧图清空、不同请求重填、重试、继续与清空失败。正文测试读取真实临时剪贴板内容，不再直接回填预期字符串。
- Bonjour 现场残留测试正文及图片已备份到 `/tmp/inkpost73-test-draft-backup.json`，经页面原生删除及清空操作处理；另开 Page 点击「发帖」确认正文为空、图片数为零。两个诊断 Page 均已结束，未发布帖子。该核验验证页面清空及持久草稿结果，不冒充正式应用完整交互验收。
- 验证：Bonjour 专项含只读在线检查 4 tests / 2 suites 通过（87.128 秒，`/tmp/inkpost73-final4.log`）。全量回归覆盖 164 tests / 31 suites（422.472 秒，在线写入测试未启用），3 个失败均为已过时断言：X 在整个脚本禁止点击而未区分附件删除，以及即刻继续执行后不再遇到旧检查点而返回原上传错误。修正断言后，X、即刻图片、fixture 专项 7 tests / 3 suites 全部通过（54.055 秒，`/tmp/inkpost73-recheck.log`）；未重复执行最终全量，不能报告最终版本单次全量全通过。构建及差异检查通过。
- 其余真实渠道的现有清空控件兼容性未在本轮逐站验收。README、需求及渠道维护文档已同步；未升版、提交、推送、安装或启动新版，Issue 尚未关闭。

### 后续真实渠道验收（2026-11-25）

- 使用临时 Swift 驱动链接当前 PublishKit 对象，直接调用实际适配器；同一适配器按 prepare → retry → resumeAfterUser 连续执行，每次输入标题、两段正文和一张 48×48 生成 PNG，全程不点击发布。测试驱动及日志位于 `/tmp/inkpost73-live-*`，不纳入产品。
- 知乎、即刻、微博、掘金三轮均返回 readyForReview，并核对正文和单张附件。知乎首次复测发现同卡片包含可见、隐藏的重复删除按钮；即刻发现悬浮删除按钮的动效尚未完成时会被提前判为不存在。已修复公共 RetryEditorReset：悬浮后等待可见删除控件，排除隐藏/透明副本，再要求唯一匹配并执行删除。对应实际复验日志：`/tmp/inkpost73-live-zhihu2.log`、`/tmp/inkpost73-live-jike2.log`、`/tmp/inkpost73-live-weibo.log`、`/tmp/inkpost73-live-juejin.log`。
- 四个渠道测试内容均通过原生页面操作清理，并回读确认文字为空、图片为零。验收 Space 10 已结束，测试页面已关闭。掘金单图为待用户发布的本地暂存，不宣称完成服务器上传；其他渠道也未实际发布。
- X 未通过：在当前真实页面，发帖弹窗使用 textarea，旧适配器仍等待 `[data-testid="tweetTextarea_0"][contenteditable="true"]`，20 秒后超时，尚未执行清空或写入。该发现与 #74 现象一致，但本轮没有修改 X 的页面结构适配，也没有把离线通过当成现场通过。证据：`/tmp/inkpost73-live-x.log` 及当前 DOM 检查。
- B站当前未登录，实际适配器返回 waitingForUser/loginRequired；用户明确选择暂时跳过 B站。未验证其登录后的清空、填写或重试，不能计为通过。日志：`/tmp/inkpost73-live-bilibili.log`。
- 公共清空修复后的离线回归 14 tests / 5 suites 通过（120.923 秒，`/tmp/inkpost73-live-regression.log`）；在线写入测试未启用。构建和差异检查通过；未提交、推送、安装或启动新版。

### X 主页发帖入口补充核验（2026-11-25）

- 按用户建议打开主页，点击实际观察到的 `a[href="/compose/post"]`。当前链接 aria-label 为「帖子」，不应绑定「发帖」文案。弹窗内为 textarea，点击入口后实测 `document.activeElement === editor`，输入为空。
- 未再点击或手动聚焦编辑器，通过现有 ClipboardPasteService 和 ImageClipboardSession 分别原生粘贴测试正文与单张 PNG，回读正文完全一致，图片预览已解码。日志 `/tmp/inkpost73-x-paste-probe.log`。图片原生移除按钮为 `button[aria-label="移除 image.png"]`，其名称包含附件文件名。
- 该入口流程可行；正式 XChannelAdapter 仍使用旧 Draft/data-testid 结构，尚未修改为此流程，不计为正式适配器验收通过。测试正文和图片已清空并回读，仅余账号头像；Space 11 已结束，未发布帖子。

### X 正式适配器更新与验收（#74，2026-11-25）

- 已将 XChannelAdapter 更新为主页入口点击 → 弹窗 textarea → 每次原生移除媒体卡片并清空正文 → 直接粘贴 → 精确回读。入口使用 href 而非本地化 aria-label；移除使用实际观察到的 `data-remove-media`，不绑定附件文件名。图片计数和有序身份使用 `data-media-tile` 与预览 URL，不包含账号头像；正文使用 textarea.value，最终按钮要求唯一、可见、可用，始终不点击。
- 复用已有请求、PNG 素材、剪贴板租约、焦点检查及执行状态，不引入第二套调度。新增 X 图片隔离回归覆盖清空重填、旧图变化、上传结果不明及超时；自动在线用例改为只读检查，避免再次遗留测试草稿。
- 使用当前 PublishKit 对象直接调用正式适配器，在主页无弹窗的状态开始，两个不同 PNG 的 prepare、retry、resumeAfterUser 三轮均 readyForReview；新适配器再填写另一份无标题、无图片稿件同样通过，确认旧正文和两图未残留。日志 `/tmp/inkpost74-live.log`，临时驱动 `/tmp/inkpost74-live-harness.swift`。这是正式适配器真实网页验证，未运行完整应用按钮链路，未发布帖子。
- 专项及相关契约 6 tests / 3 suites 通过（62.596 秒，`/tmp/inkpost74-final-tests.log`），含只读在线结构检查；构建通过。初轮新增图片测试中，超时错误仍从底层桥接抛出、由公共分发映射，已修正误把直接适配器错误当作已映射错误的断言。未重新运行全量回归。
- 最终回读测试正文为空、媒体卡片为零，Space 12 已结束，测试页面关闭。维护文档及需求同步；未提交、推送、升版、安装或启动新版，未关闭远端 Issue。此记录取代前面「X 正式适配器未通过/尚未更新」的阶段状态；B站仍按用户要求跳过。

- 0.26.0 交付复核：全量串行回归通过（165 tests / 32 suites，468.131 秒）。正式签名构建、DMG 完整性、ZIP 解压验签、版本、SHA256 和更新清单校验通过。

### 适配器点击等待与附件检查（#72）

七个正式渠道的显式点击统一通过公共操作，点击后随机等待 300～800 毫秒。各渠道继续核对编辑器、焦点、附件数量或文件选择器等实际状态。文件选择器监听先于点击，焦点确认先于键盘输入。

有图任务在最终回读前检查编辑器溢出，并按需滚动编辑器、弹窗或页面以露出附件。最终仍由渠道核对正文和有序附件状态。Bonjour 的本地预览和掘金的待发布附件沿用各自判定。浏览器操作沿用任务取消与写入不明时的人工检查流程。

验证：独立构建目录编译通过，串行回归运行报告 165 项测试、32 个套件通过（真实渠道在线用例未启用）。ego Lite 本地测试页验证了慢组件就绪等待、长文本和嵌套容器滚到底及正文保留；脚本检查覆盖 300/800 毫秒边界和短正文无需滚动。七渠道真实页面验收及各平台明确限制提示的识别覆盖仍待核实。

## 公共 AI 接入（#56）

- 参考 Echo 的钥匙串、模型获取及请求生命周期设计。AISettings 保存非敏感配置和墨驿专属密钥，AIClient 提供 OpenAI 兼容 models 与 chat/completions 调用，AISettingsController 管理设置操作，AISettingsView 负责显示。
- 远程接口要求 HTTPS，本机 HTTP 支持 localhost 和回环地址。拒绝带用户信息、查询参数及完整操作路径的基础地址。拒绝重定向，错误仅展示 HTTP 状态，不展示响应正文或凭据。
- 获取模型不代表文本调用成功；测试连接使用选定模型发送固定测试文字。超时 60 秒，可取消，使用请求身份隔离迟到结果。
