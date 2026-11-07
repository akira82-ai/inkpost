# Zhihu adapter maintenance

Read this document before changing `ZhihuChannelAdapter.swift`. Common architecture, communication contracts and browser reliability rules remain in the repository root `AGENTS.md`; this document owns Zhihu-specific rules and verified workflow details.

## Channel rules

- Support thoughts (想法) only, using the home-page composer at `https://www.zhihu.com/`, not column articles.
- Receive the complete `ChannelRequest`, including title, full body, HTML, tags and all images. Title is optional; when supplied, fill the independent title control and verify its accepted value. The configured input contract allows up to 44 title characters and 1899 body characters including appended tags and line breaks, counted with Swift String.count. Reject excess without truncation or title generation; also honor exposed editor constraints.
- Fill and verify a supplied title, then the complete body and tags, then all supplied images, and stop before the final 发想法 action. Do not assume the editor has saved a durable draft.

## Verified browser workflow

- Restrict navigation to the home page. Deterministically expand the thought composer by clicking 分享此刻的想法 before waiting for visible title/body controls. Do not expose arbitrary click to repair this activation step.
- Never send Escape to dismiss topic suggestions: it collapses the thoughts composer even with content. Paste the complete body and tags once, then paste images sequentially, waiting for each upload. Fill a supplied title through its native field before body/image paste; do not add a title-field click after body paste or dismiss topic suggestions.
- Use the shared clipboard service/session for app-managed PNG writes and ego Lite `Meta+V`, one image at a time. Wait for an HTTPS-backed loaded attachment and absence of its upload spinner; count attachment tiles, not duplicated image previews.
- Resume with the original request, adapter and Page. Preserve confirmed upload progress; unknown previous paste results require manual inspection rather than blind retry. Restore the prior clipboard only while the app still owns its change count; preserve newer user copies.
- Verify the accepted title, complete expected body and the uploaded attachments before returning `readyForReview`. Return contract-defined stages, outcomes and failures; channel instructions and browser selectors stay inside this adapter.

## Verification history and remaining coverage

- Earlier live checks using generated images verified two-image upload, repeat-run deduplication, complete body verification and clipboard restoration. These are historical observations, not a guarantee against future website changes.
- The Escape collapse was reproduced; the flow without Escape was verified in the same failing Space.
- Login expiry, network failures and concurrent user clipboard changes still need live fault-injection testing. Preserve content and report the failing step when behavior is uncertain; do not claim these cases are covered without evidence.

- Verify logical Draft blocks joined by line breaks, preserving spaces and empty paragraphs; visual innerText is not the equality source. Recovery checkpoints compare ordered remote attachment origin/path identities without signed queries; replacement, reordering or unknown paste outcomes require inspection.

- 2026-11-07: shared execution contracts no longer carry model configuration or a model-requirement capability. Browser steps and channel input rules are unchanged; offline regressions passed, with no live platform writes in this cleanup.
