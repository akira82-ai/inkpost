// sim 适配器：驱动本地 fixture 页面，验证引擎全链路。
// 仅使用官方 helper（见 lite.ego.app/docs/ego-browser）：
//   useOrCreateTaskSpace / openOrReuseTab / gotoAndWait / fillInput /
//   uploadFile / click / js / cliLog
//
// run(TASK, step) 由引擎生成的引导脚本调用；TASK 为 PublishTask JSON。
// 返回约定：{ ok, phase, message?, url?, draftURL? }

export async function run(TASK, step) {
  if (step === "prepare") return await prepare(TASK);
  if (step === "finalize") return await finalize(TASK);
  return { ok: false, phase: "failed", message: `未知步骤 ${step}` };
}

// 稳健导航：新建 Space 的首批导航偶发竞态（chrome-error / about:blank / CDP Invalid parameters）。
// 策略：导航 → 校验 pageInfo.url → 未到位则退避并交替用 openOrReuseTab / gotoAndWait 修正。
async function navTo(url) {
  await openOrReuseTab(url, { wait: true, timeout: 20 });
  await wait(1);
  let lastInfo = null;
  for (let i = 0; i < 8; i++) {
    lastInfo = await pageInfo();
    const u = lastInfo.url || "";
    if (u === url) return;
    await wait(1.2 + i * 0.4);
    try {
      if (i % 2 === 0) {
        await gotoAndWait(url, { timeout: 20, settle: 1 });
      } else {
        await openOrReuseTab(url, { wait: true, timeout: 20 });
      }
    } catch (e) {
      // 竞态兜底：下一轮重试
    }
  }
  const tabs = await listTabs();
  throw new Error(`导航失败，当前页面: ${lastInfo?.url || "?"}；tabs=${JSON.stringify(tabs).slice(0, 400)}`);
}

async function prepare(TASK) {
  const task = await useOrCreateTaskSpace(TASK.spaceName);
  // 官方要求：新建的 Space 可能还没有真实 tab
  await ensureRealTab();
  await navTo(TASK.editorURL);

  // 1) 标题
  await fillInput('input#title', TASK.article.title);

  // 2) 素材（happy path：单图；多图在真实适配器中扩展）
  if (TASK.assets && TASK.assets.length > 0) {
    await uploadFile('input#files', TASK.assets[0].path);
  }

  // 3) Plain text only; preserve whitespace, newlines and emoji.
  await fillInput('#editor', TASK.article.markdown);
  const bodyOK = await js(`document.querySelector('#editor').value === ${JSON.stringify(TASK.article.markdown)}`);
  if (!bodyOK) {
    return { ok: false, phase: "failed", message: "正文写入校验失败" };
  }

  // 4) 回读标题做最终校验
  const titleOK = await js(`document.querySelector('input#title').value === ${JSON.stringify(TASK.article.title)}`);
  if (!titleOK) {
    return { ok: false, phase: "failed", message: "标题写入校验失败" };
  }

  return {
    ok: true,
    phase: "awaitingConfirm",
    message: "草稿已就绪。请在 ego 浏览器中检查内容，点击页面上的「确认发布」。",
    draftURL: TASK.editorURL,
  };
}

async function finalize(TASK) {
  const task = await useOrCreateTaskSpace(TASK.spaceName);
  await ensureRealTab();
  // finalize 只读页面状态，不导航，规避竞态；页面在 prepare 时已打开
  const existing = await listTabs();
  const onFixture = existing.some(t => (t.url || "").startsWith("file://"));
  if (!onFixture) {
    await openOrReuseTab(TASK.editorURL, { wait: true, timeout: 20 });
  }

  // 用户是否已在页面上点击「确认发布」（fixture 用 #receipt 标记发布结果）
  const receiptURL = await js(
    `(() => {
      const el = document.querySelector('#receipt');
      return el && el.dataset.url ? el.dataset.url : null;
    })()`
  );

  if (!receiptURL) {
    return { ok: false, phase: "awaitingConfirm", message: "尚未发布：请在 ego 浏览器的该页面点击「确认发布」后重试。" };
  }
  return { ok: true, phase: "published", url: receiptURL };
}
