# 微博普通图文动态适配器

## 已验证入口与内容规则

2026-11-08，ego Lite 登录态实测 `https://weibo.com/` 顶部 `button[title="发微博"]`，点击进入「快捷发布」。
限定正文定位：`.woo-modal-main .wbpro-layer textarea[placeholder="有什么新鲜事想分享给大家？"]`。
打开面板后等待自动聚焦完成（动画开始时 activeElement 仍可能是按钮），再直接 `keyboard.press('Meta+V')`；不额外点击正文。
每次操作前确认唯一快捷发布面板及标题；焦点因交接等原因丢失时，用原生 focus 恢复到已确认的面板正文，不能对任意 activeElement 粘贴。
实测正文和两张 PNG 可连续原生粘贴，行首／行尾空格、空行和 emoji 保留。
没有独立标题栏：标题非空时按「原始标题 + 一个换行 + 原始正文」组合后粘贴并校验；标题为空时只写原始正文，不新增换行。不 trim 标题或正文，兼容 HTML 不使用；原始 ChannelRequest 保持完整。
标签属于正文，不解析、不生成、不 trim。仅空白正文报 contentUnsupported。
未确认跨账号统一字数／图片上限，能力不虚构限制；产品编辑器仍限制六张图片。
最终核对实际发送按钮可用性与页面错误，绝不点击发送、头条文章、视频或定时微博。

## 原生图片粘贴与校验

仅使用任务 AssetService 准备的 PNG，独占 ImageClipboardSession 并有条件恢复剪贴板。
聚焦上述 textarea，逐张 `keyboard.press('Meta+V')`。已实测两张 PNG 的顺序上传。
发布卡片为正文最近的 `div[class^="_box_"]`，要求含文件输入和唯一“发送”按钮。
附件为卡片内 `div[class^="_picbed_"]`，排除包含文件输入的“添加”格。
上传中附件只有 `.woo-spinner-main`；完成后出现 sinaimg.cn 远程 img。
核对 img.complete、naturalWidth、远程地址、无 spinner，按 DOM 顺序记录 origin/path（不留签名查询串）。
不用全页面 img 计数，避免头像、声明图标及推荐流干扰。
首页会自动恢复草稿，但它不是操作目标，快捷发布与首页的同名 textarea 必须分开定位。
快捷发布如已有不同正文或未知附件，保留并提示检查，不自动清空；已观察到空白打开，不将“每次必为空”作为假设。
验证结束清理本次创建的测试正文与图片，避免留下测试草稿。
这些 CSS 模块名前缀来自实测；结构不匹配时停止报错，不能猜测另一个入口或写 DOM 内部状态。

## 恢复与失败

同一任务复用适配器、Page、原始请求及 prepared PNG。登录入口或可见登录按钮且编辑器缺失时返回 loginRequired。
首次记录面板打开尝试后才执行点击；结果不明时不盲目重放打开动作。
恢复不刷新，不重开面板，不覆盖已存在的其他正文，不重新粘贴已确认附件。面板关闭或不唯一返回 editorUnavailable / inspectionRequired。
粘贴前记录 pending；上传超时后仅等待原附件，无法确认粘贴结果时转 inspectionRequired，不盲目重放。
附件删除、替换、重排或额外添加均停止，保留页面。正文粘贴结果不明且框为空时也不自动重复。
取消沿共享执行器传播；已完成的页面操作不回滚。任务身份、重复命令和变更快照由通用协调层拒绝。

## 验证与边界

离线进程替身调用真实适配器，覆盖正文、登录恢复、冲突、拒绝、取消、附件检查点、未知写入、超时及重排。
`INKPOST_WEIBO_LIVE=1`、`INKPOST_WEIBO_LIVE_SPACE`、`INKPOST_WEIBO_LIVE_PAGE` 可运行真实页面填写／恢复测试，必须指定本任务专用 Page（首页可有旧草稿，快捷发布需为空），不发布。
登录退出／上传中登录过期、实际网络故障和不同账号上限尚需专项验证，替身测试不等于真实故障回归。

## Temporary clipboard writes (#55)

Text paste uses `ClipboardPasteService.withTextPaste(text)` to write plain text and `org.nspasteboard.TransientType` in one pasteboard item, followed by native `Meta+V`. Do not call `keyboard.paste(text)` here: that would rewrite the marked clipboard. PNG clipboard uploads share the same marker and lease. Restore only while the app owns the pasteboard change count; never overwrite a newer user copy. This remains native paste, not direct DOM editing. Channel-specific live compatibility after this change still requires verification.
