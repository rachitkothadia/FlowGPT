# FlowGPT 1.3.2 for Windows

This Windows update addresses missing transcripts, sign-in startup registration and unclear UI status. Mac remains on 1.3.1.

## Recording and missing History

Three concrete code defects were found. They can produce the reported symptom; the exact path on the user's physical laptop has not been observed directly.

1. An unsupported insertion target used to cancel capture before transcription, losing the chance to save History. Target availability now controls insertion only. A completed transcript is saved even when automatic typing is unavailable or target discovery is still pending.
2. The composer can retain a visible Dictate button behind an active recorder. That idle-looking control used to prematurely stop recording. An active recorder now takes precedence.
3. Idle controls can return before React inserts the transcript. An empty intermediate snapshot used to be rejected immediately. Empty results now receive a bounded grace window; actual text still uses the existing stability check without waiting out that empty-result window.

Repeated connection-probe failures are no longer silently ignored. Failures show a red recording indicator for four seconds and a silent tray notification. Clicking the indicator opens the explanation. Transcripts that cannot be inserted remain available through Home's Copy text button and History. Diagnostics now identify the current version, recorder phase, queued audio, target availability and capture state without exporting dictated text or login credentials.

## Startup and connection

The installer and app share a saved per-user startup preference. A normal launch repairs missing/stale startup registration when enabled; an explicit opt-out remains off through silent updates. Startup uses the supported per-user Run entry with the quoted EXE path and `--background` argument. Windows' own disabled-startup decisions are not overwritten. Startup settings link directly to Windows Settings.

The existing WebView2 sign-in profile, local transcripts and user settings are preserved. A provider-expired ChatGPT login still requires the account owner to sign in again.

## Interface

- Green check and colored badge for a verified ChatGPT connection; clear connecting/sign-in states.
- Separate microphone on/idle/error status, native icons and an outlined shortcut card.
- Compact native layout, direct Copy text action, consistent rounded corners and explicit startup controls.
- Recording errors have a visible failure state instead of disappearing like successful completion.

## Verification scope

Portable tests cover the recorder-state precedence and insertion eligibility rules. The Windows native suite now drives the actual AppController with an isolated synthetic audio source through WebView2 capture, delayed transcript return, History persistence and the unavailable-target path. The fixture deliberately leaves Dictate visible during recording and restores idle controls before text arrives.

Registry tests use disposable test keys. Installer tests cover registration without a forced startup task, opt-out preservation, opted-in repair, upgrade data preservation and background lifecycle. The UI suite checks connection badges, navigation, themes, close-to-tray and shortcuts. These are software/fixture checks; physical microphone/account behavior on the user's laptop and a real sign-out/sign-in cycle require device verification.

Packaged release evidence is appended after the Windows build completes.
