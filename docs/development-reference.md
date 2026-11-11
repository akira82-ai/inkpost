# 开发参考资料

以下内容从 AGENTS.md 移出，保留为既有技术方案与操作参考，不作为新需求的约束，也不代表这些方案必须继续沿用。涉及变更时以用户确认的需求、当前代码和实际验证结果为准。

## 发布版本号

- **Patch**：修复已有能力，例如修正渠道图片排序或在线更新失败（`0.18.0 → 0.18.1`）。
- **Minor**：新增向后兼容的用户能力，例如新增可用渠道，或已有渠道首次支持一种内容类型（`0.18.0 → 0.19.0`）。渠道以用户能在正式应用中选到并完成该渠道承诺的操作为准；只有适配器、尚未开放入口时，不单独升 minor。
- **破坏兼容性**：在 `0.x` 阶段升 minor，在 Release 开头说明受影响范围和迁移办法；进入 `1.x` 后升 major。`1.0.0` 留到项目准备公开承诺兼容性时发布。
- 纯内部重构、测试、格式、注释或维护文档不单独升版本；同一次发布包含多类改动时，按影响最大的类别升一次。

## 代码组织

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
