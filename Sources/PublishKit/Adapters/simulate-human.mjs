// 冒烟测试专用：代替「人工」在 fixture 页面上点击「确认发布」。
// 产品真实流程中，这一步由用户在 ego 浏览器里亲手完成，脚本不存在。

export async function run(TASK, step) {
  const task = await useOrCreateTaskSpace(TASK.spaceName);
  await ensureRealTab();
  await openOrReuseTab(TASK.editorURL, { wait: true, timeout: 20 });
  await click('#publish-btn', { label: '模拟人工点击确认发布' });
  await wait(0.5);
  const url = await js(`(() => { const el = document.querySelector('#receipt'); return el && el.dataset.url ? el.dataset.url : null; })()`);
  cliLog(JSON.stringify({ ok: !!url, url }));
}
