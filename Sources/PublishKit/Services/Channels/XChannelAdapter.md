# X adapter maintenance

## Input and execution

- Deterministic adapter; no model or API key. Open `https://x.com/home`, click the unique `a[href="/compose/post"]` entry, and wait for the visible dialog textarea. Reuse an already open compose dialog on retry/resume. Do not bind the entry to localized aria-label text (observed: 帖子).
- Receive all fields. Compose optional title + one newline + body. Preserve body whitespace, line breaks and emoji as plain text; HTML is unused.
- The user-specified product limit is 1899 Swift String.count characters for the entire composed text and at most four images. This is not a claim about universal X account limits. Honor visible rejection and require exactly one visible form button whose text is 发帖 or Post to be enabled before success, without clicking it.
- Body is mandatory; title and images are optional. Reject excess before writing, never truncate or select an image subset.
- Read `[role="dialog"] textarea.value` exactly, preserving spaces and line breaks. Require one visible editor. The background home textarea is outside the dialog; never target it. The former Draft/data-testid structure is no longer supported.
- First check actual focus. If needed use native page.focus on the observed dialog editor, then native keyboard.press('Meta+V'). Do not click or mutate editor internals. The current homepage entry auto-focused the textarea in the 2026-11-25 live check; still verify focus before native paste because reset or user interaction can move it.
- Paste app-managed PNG images one at a time using the shared clipboard lease and Meta+V. Wait for attachment previews, absence of upload progress, and enabled Post button; X uses blob preview URLs, so HTTPS-backed preview is not required. Count `[data-media-tile]` cards inside the dialog, never profile pictures. Each card must contain one decoded img and one `button[data-remove-media]`; its ordered identity includes tile ID and preview URL. Remove each old card via this native button, wait for the count to decrease, then clear the textarea and verify empty text/attachments. Variable filenames in aria-label are not selectors.
- Task-local ordered preview URL checkpoints detect removal/replacement/reordering. Set pending before dispatch; unknown outcomes require user inspection, never paste blindly again. Reuse the same page and original snapshot for resume; clear its composer before refilling, without reloading the page.
- Clipboard ownership and conditional restoration reuse ImageClipboardSession. Cancellation propagates. Never click Post or dismiss a populated composer.

## Verification

- 2026-11-07: real editor verified title/body/empty paragraph/leading spaces and two native PNG pastes. Same adapter resume verified no duplicate text/images; Post remained unclicked.
- Offline tests cover composition, limits, unicode, login/resume, conflicting content, rejection, cancellation and repeat-run text deduplication.
- Opt-in live test requires `INKPOST_X_LIVE=1`, `INKPOST_X_LIVE_SPACE` (an owned, existing Space name) and `INKPOST_X_LIVE_PAGE` (a managed Page with the composer already open). It only checks editor/button structure; it does not write or clear real-account drafts. Full native paste/reset checks require an explicitly authorized disposable draft and cleanup afterward; never publish.
- Live login expiration, network failure, four-image upload and concurrent clipboard modification still require fault-injection coverage. Blob preview + enabled Post is a UI readiness check, not server-side publication or durable draft proof.

- 2026-11-07: shared execution contracts no longer carry model configuration or a model-requirement capability. Browser steps and channel input rules are unchanged; offline regressions passed, with no live platform writes in this cleanup.

- PNG preparation contract (#30): AssetService prepares the complete ordered PNG batch before browser execution. Receive the unchanged original ChannelRequest and obtain final PNG upload paths through `context.uploadPaths(for:)`. Never convert formats, repair input, or fall back to original files in this adapter. DispatchService retains the same batch during login waits and resume. Clipboard writes copy validated PNG bytes unchanged.

- Raw input contract (#9): body is plain text, including whitespace, line breaks and emoji. Preserve every character without rendering or content processing. Explicit HTML remains an unused compatibility field. Task-prepared PNG mappings stay separate from the original request.

## Temporary clipboard writes (#55)

Text paste uses `ClipboardPasteService.withTextPaste(text)` to write plain text and `org.nspasteboard.TransientType` in one pasteboard item, followed by native `Meta+V`. Do not call `keyboard.paste(text)` here: that would rewrite the marked clipboard. PNG clipboard uploads share the same marker and lease. Restore only while the app owns the pasteboard change count; never overwrite a newer user copy. This remains native paste, not direct DOM editing. Channel-specific live compatibility after this change still requires verification.

- Every execution (prepare, retry, and resume) must clear the target title (when present), body, and all attachments before filling the complete current task snapshot. Verify empty fields and zero attachments first; only then reset paste/upload checkpoints. A failed clear stops before any new paste. Reuse the existing native clear implementation; never click final Publish.
