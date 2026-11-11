# Bilibili ordinary dynamics adapter

## Scope

- Only `https://t.bilibili.com/` ordinary text/image dynamics. No articles, videos, topic selection, scheduling or final publication.
- Reuse ChannelRequest, ChannelExecutionContext, ClipboardPasteService, AssetService and the task's assigned Page. Title and body are separate fields; empty title is skipped, HTML is unused. Never trim, truncate, generate a title or append tags to the request.
- The observed title input has `maxlength=20` (UTF-16 units). Fail before writing overlong titles. No verified body/image ceiling is asserted; the product limits selected images to six. Website restrictions are not guessed from other channels.

## Observed workflow (2026-11-10, ego Lite)

- Logged-in composer: `.bili-dyn-publishing`, title `.bili-dyn-publishing__title__input`, body `.bili-rich-textarea__inner[contenteditable="true"]`. Click each field before native keyboard.paste; do not assign DOM/framework state.
- Empty editor contains exactly U+200B and LF with the `empty` class. Plain paste produces U+200B + text + SPACE + LF. Read only text nodes and remove exactly these observed editor sentinels, never trim user content. Unknown structures fail verification rather than silently flattening mentions or other rich tokens.
- Plain multiline text, empty paragraphs and emoji were verified. Bilibili itself trims edge whitespace during paste. This adapter reports a mismatch and preserves the page if raw input cannot be verified; it does not claim arbitrary whitespace survives. Final publication was never invoked or verified.
- Clear existing title, body and images once before the first fill. Read back all three to confirm they are empty. A failed or uncertain clear stops filling; resume never clears again. Uncertain pastes are not replayed.
- First upload uses `.bili-dyn-publishing__tools__item.pic` if the upload area is collapsed. Once expanded, use `.bili-pics-uploader__add`. The toolbar icon toggles the area; clicking it again can hide it instead of opening a chooser. Observe visibility first, arm waitForFileChooser before clicking, and add one prepared PNG at a time.
- Attachments: `.bili-pics-uploader__item.success`, preview `.bili-pics-uploader-item-preview__pic` CSS background with data image URL; the preview's `msg` attribute reports errors. Decode each image and hash its stable data URL with dimensions for ordered recovery checkpoints. Success class and decoded preview are both required; do not infer successful upload from a dispatched chooser action.
- Two distinct 64×64 pure-color PNGs were successfully added in order. Never use user/account screenshots as disposable upload fixtures. Initial batch chooser and incremental additions were both exercised; six-image and maximum-size limits are unverified.
- Final readiness reads the unique `.bili-dyn-publishing__action.launcher` class/aria state, never clicks it. Explicit visible login controls produce waitingForUser; timeouts are not classified as login. Actual logout/expired session UI still requires live fault injection.

## Verification

- Real adapter through injected CLI tests covers raw request comparison, title UTF-16 limit, empty body, login resume, preexisting draft replacement and failed clearing, uncertain title/body/image writes, timeout, blocked/rejected state, external title/body edits, ordered image deletion/replacement/reordering, cancellation and PNG paths.
- Opt-in live test: `INKPOST_BILIBILI_LIVE=1`, `INKPOST_BILIBILI_SPACE` set to the agent-owned test Space name. Requires `/tmp/inkpost-bili-test-1.png` and `-2.png`. It clears only the disposable test Page, runs no-title/no-image and title/two-image cases, then resumes the same adapters without duplicate writes; an edge-whitespace case must fail exact verification. Test cleanup must hover each image tile before clicking its remove control and wait for the count to decrease. Avoid reloading between cases: the website asynchronously restores old draft attachments during startup. It never publishes. Do not run against a user's draft Page.
- Live and automated results are recorded in docs/development-reference.md. Network interruption, expired login, account restrictions and maximum image acceptance remain unverified in live browser testing.
