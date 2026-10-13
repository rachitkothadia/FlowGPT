# Contributing to FlowGPT

FlowGPT is a native Swift macOS app. The current recording path uses a hidden WebKit ChatGPT session. Historical Groq and continuous-recording code remains in the tree, but does not define current behavior.

## Development

Use Swift 6.2+ and a compatible macOS SDK. Run `Scripts/test.sh` and `swift build -c release -Xswiftc -warnings-as-errors` before submitting changes. Use `swift run FlowGpt --design-preview` for an isolated UI preview; its data and connection states are illustrative.

Keep changes focused. Add regression coverage for state transitions, audio ordering, cancellation, persistence, or insertion behavior when those change. A unit test count is not a speech accuracy result. Mark live microphone, website, shortcut, and destination-editor checks separately.

## Behavior to preserve

- Record only after an explicit user action, and freeze native capture when finishing.
- Preserve opening audio, report overflow, and never silently drop or reorder samples.
- Save the transcript before clearing its matching browser draft or attempting insertion.
- Preserve user clipboard content, including new copies made during insertion.
- Do not reload active dictation, existing drafts, or login pages automatically.
- Do not reset macOS privacy grants or modify the TCC database.
- Do not bundle account sessions, keys, personal transcripts, or recordings.

Public binaries require Developer ID signing and Apple notarization. Consult [distribution instructions](Docs/DISTRIBUTION.md) before publishing installers.

## Reporting bugs

Include macOS version, Apple Silicon/Intel, app version, exact reproduction steps, and the observed result. Redact screenshots and terminal output before sharing. For audio recognition examples, include the intended and actual text only when you have permission to share it.

## Repository navigation

If Graphify is installed, use scoped queries before cross-file changes and `graphify update .` afterward. Generated graphs are local navigation artifacts and are not committed. The real source is the authority.
