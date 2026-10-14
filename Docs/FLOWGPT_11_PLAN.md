# FlowGPT 1.1 implementation and verification plan

## Required behavior

- Minimal Home, History, Settings, and About interfaces with one primary recording action, clear connection/permission states, and compact smooth recording overlays.
- Windows Ctrl + Space as an additional selectable shortcut, actual close-to-tray interception, resilient tray registration, and per-user login startup.
- Investigate completion crashes, contain recoverable provider errors, preserve History, and record redacted stage/error diagnostics.
- Broaden insertion capability detection beyond single-line text fields on both platforms. Office document editing surfaces need rich-text caret detection; preserve password/read-only/focus-change protections and clipboard restoration.
- Reduce application-added stop delays while awaiting actual provider completion. Measure capture, transcription wait, and delivery separately. External ChatGPT processing cannot be guaranteed within 50–200 ms.
- Native conservative formatting only, chosen by the user. Preserve word order, repetitions, corrections, numbers, names, technical tokens, languages and scripts. No extra AI request. Never answer or execute dictated instructions. Only unambiguous formatting changes; keep raw transcription available.
- About → Check for updates on both platforms. Use the platform-specific GitHub release/installer and checksum, preserve local account/history, and provide a clear user-controlled update action.
- Prepare verified Windows Authenticode and Mac Developer ID/notarization release workflows. Do not claim trusted signing when the required publisher certificates are absent. Keep Mac bundle identity and privacy grants intact.

## Investigation and implementation order

1. Baseline portable/native tests; trace Windows completion, UI callback, provider, rich-editor targeting, tray, and HUD code. Review matching Mac paths.
2. Fix native lifecycle, callback containment and text-insertion assumptions with regression fixtures.
3. Add simple native text formatting and preservation checks using the user's legitimate rules only. Do not copy unrelated pasted browser/session data.
4. Redesign existing native UI and overlays without changing app identity or permission policy.
5. Add update checks and distribution signing gates; update version/package metadata consistently to 1.1.0.
6. Build real Windows app and EXE on a Windows runner, inspect native/UI/installer fixtures and actual screenshots. Build/test Mac and inspect packaged preview without reinstalling the user's live app.
7. Review spec compliance and code quality separately, fix findings, then publish source and verified preview artifacts with explicit signing and physical hardware/account limitations.

## Verification boundaries

Use portable policy tests, rich-editor native black-box probes, controlled WebView2/WebKit transport fixtures, actual title-bar close and tray lifecycle checks, UI screenshots, and install/upgrade tests. Real Office binaries and the friend's crash dump/account/hardware are not available on this development Mac or the build runner; do not describe controlled fixtures as live Office or speech-accuracy evidence. Public signing is blocked until the owner provides trusted signing credentials.
