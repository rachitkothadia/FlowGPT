# Flow 3.0.1 insertion update

The user approved automatic paste with clipboard restoration. Native writable fields keep selected-text insertion. Browser and custom editors now receive one native Command-V paste, with explicit modifiers and delivery directed to the captured application. Flow snapshots every readable item and format in memory, restores them after delivery, and leaves a newer user copy alone. Snapshot failure prevents clipboard mutation. Cancellation after posting allows consumption time before restoration. No full-text replay follows an uncertain delivery.

The original focused field, application, window and available document identity are checked before delivery. A recreated field is accepted only with the same nonempty stable identifier, document and window. The focused editable ancestor can handle nested editor children. Secure and read-only fields are refused. Electron's documented AXManualAccessibility attribute can expose its editor tree without changing macOS privacy grants. Accessibility, Input Monitoring, microphone and shortcut service files are unchanged.

## Validation, 11 October 2026

- Automated suite: 124 tests in 13 suites passed, including eight new insertion-safety/clipboard tests. Tests cover window/document changes, recreated field identity, multiple clipboard formats/items, empty clipboard, concurrent copying, unavailable promised data, failed writes and snapshot races.
- Production NativeClipboard check on a private named macOS pasteboard passed: valid rich text plus a separate binary item, every readable format restored, empty restoration and preservation of a newer copy. The user's clipboard is untouched by this check.
- Actual production InsertionService in Opera GX: local multiline textarea and custom contenteditable both confirmed the complete multilingual text, emoji, technical symbols and newline. The diagnostic verified all original clipboard formats were restored; CUA readback independently showed the inserted text.
- Password field: actual production adapter refused delivery; field remained empty.
- Read-only field: actual production adapter refused delivery; its original value remained unchanged.
- Real YouTube search: the production adapter inserted a single-line Hindi/English/emoji/technical string and confirmed its value. A second run using the packaged release executable also confirmed insertion. Both verified all clipboard formats restored. No query or comment was submitted.
- Final native release suite: 124 tests in 13 suites passed. Release compilation with warnings treated as errors, bundle self-check, native named-pasteboard check and strict ad hoc signature verification passed.

The browser checks test the delivery adapter directly with synthetic text, not microphone capture or speech recognition. The packaged release executable was used for the final YouTube search check. Local editor tests used the debug executable built from this implementation.

## Limits

Computer-control tooling denies access to the Codex desktop app. Its live input test was therefore not performed or bypassed. Browser tests cover the installed Opera GX rather than every browser or editor. Remote desktops, secure input and editors that suppress paste or fail to expose editable focus can still be incompatible. A posted event without matching readback is marked attempted, never confirmed or automatically replayed. Recognition/transcription accuracy is unchanged by this insertion update.

The installed app and macOS permission entries are not replaced/reset during this build. The root DMG contains an ad hoc signed local build; no Developer ID or notarization is claimed. A changed ad hoc signature can still cause macOS to reassess an existing grant on installation.

## Reference

[Electron accessibility documentation](https://github.com/electron/electron/blob/main/docs/tutorial/accessibility.md) documents AXManualAccessibility for external assistive applications. [Apple's Unicode keyboard event documentation](https://developer.apple.com/documentation/coregraphics/cgevent/keyboardsetunicodestring%28stringlength%3Aunicodestring%3A%29) cautions that application frameworks may ignore the supplied Unicode string. Native paste avoids relying on that mechanism for browser editors.
