# X adapter maintenance

## Input and execution

- Deterministic adapter; no model or API key. Open only `https://x.com/compose/post`.
- Receive all fields. Compose optional title + one newline + body. Preserve body whitespace, line breaks and emoji as plain text; HTML is unused.
- The user-specified product limit is 1899 Swift String.count characters for the entire composed text and at most four images. This is not a claim about universal X account limits. Honor visible rejection and require the actual Post button to be enabled before success, without clicking it.
- Body is mandatory; title and images are optional. Reject excess before writing, never truncate or select an image subset.
- Read the dialog's `tweetTextarea_0` Draft blocks joined by newlines. The background home composer has a different editor; never target it.
- First check actual focus. If needed use native page.focus on the observed dialog editor, then native keyboard.press('Meta+V'). Do not click or mutate editor internals. The assumption of automatic focus failed in the live check: focus was on the modal container and direct paste inserted nothing.
- Paste app-managed PNG images one at a time using the shared clipboard lease and Meta+V. Wait for attachment previews, absence of upload progress, and enabled Post button; X uses blob preview URLs, so HTTPS-backed preview is not required. Count attachment images within the dialog's attachments region, never profile pictures.
- Task-local ordered preview URL checkpoints detect removal/replacement/reordering. Set pending before dispatch; unknown outcomes require user inspection, never paste blindly again. Reuse the same page and original snapshot for resume, do not reload an existing compose page.
- Clipboard ownership and conditional restoration reuse ImageClipboardSession. Cancellation propagates. Never click Post or dismiss a populated composer.

## Verification

- 2026-11-07: real editor verified title/body/empty paragraph/leading spaces and two native PNG pastes. Same adapter resume verified no duplicate text/images; Post remained unclicked.
- Offline tests cover composition, limits, unicode, login/resume, conflicting content, rejection, cancellation and repeat-run text deduplication.
- Opt-in live test requires `INKPOST_X_LIVE=1`, `INKPOST_X_LIVE_SPACE` (an owned, existing Space name) and `INKPOST_X_LIVE_PAGE` (a fresh managed Page label). It writes generated text and images, leaves the composer open, and never publishes. Do not run against a user's existing draft.
- Live login expiration, network failure, four-image upload and concurrent clipboard modification still require fault-injection coverage. Blob preview + enabled Post is a UI readiness check, not server-side publication or durable draft proof.

- 2026-11-07: shared execution contracts no longer carry model configuration or a model-requirement capability. Browser steps and channel input rules are unchanged; offline regressions passed, with no live platform writes in this cleanup.

- PNG preparation contract (#30): AssetService prepares the complete ordered PNG batch before browser execution. Receive the unchanged original ChannelRequest and obtain final PNG upload paths through `context.uploadPaths(for:)`. Never convert formats, repair input, or fall back to original files in this adapter. DispatchService retains the same batch during login waits and resume. Clipboard writes copy validated PNG bytes unchanged.

- Raw input contract (#9): body is plain text, including whitespace, line breaks and emoji. Preserve every character without rendering or content processing. Explicit HTML remains an unused compatibility field. Task-prepared PNG mappings stay separate from the original request.

## Temporary clipboard writes (#55)

Text paste uses `ClipboardPasteService.withTextPaste(text)` to write plain text and `org.nspasteboard.TransientType` in one pasteboard item, followed by native `Meta+V`. Do not call `keyboard.paste(text)` here: that would rewrite the marked clipboard. PNG clipboard uploads share the same marker and lease. Restore only while the app owns the pasteboard change count; never overwrite a newer user copy. This remains native paste, not direct DOM editing. Channel-specific live compatibility after this change still requires verification.
