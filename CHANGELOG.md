# Changelog

## 1.3.2 (Windows)

- Preserve dictation and History when the target field cannot accept automatic typing.
- Keep recording active when idle composer controls remain visible behind the recorder.
- Wait for delayed transcript insertion instead of rejecting an intermediate empty composer.
- Repair missing startup registration on launch and persist startup opt-out through silent updates.
- Add colored ChatGPT/microphone status badges, native icons, shortcut cards and a direct Copy text action.
- Show recording failures with a red popup indicator and a silent tray notification.
- Add full controller capture-to-History fixtures with synthetic audio and delayed provider text.

## 1.3.1

- Keep declared list items and their explanatory sentences together across sentence boundaries.
- Keep leading connectors with their following item; repair connector-only bullet fragments outside code and quotes.
- Continue a clear list after an addressed question when an additional item is spoken, without requiring a price.
- Format untouched prose around existing bullets; preserve already-formatted list spacing and quoted/code content.
- Add the full reported bilingual example and cross-domain regression cases.

## 1.3.0

- Detect coordinated item phrases and parallel actions without mandatory list-introduction words; keep full conversational clauses separate.
- Use circle bullets (•), remove separator commas between items, preserve interruptions in spoken order, and number procedural actions.
- Normalize identifiable currency expressions using bundled Unicode CLDR data covering 307 currency identifiers and 23 locales; preserve ambiguous names, literal quotations and code.
- Preserve original transcripts in History, with no extra network request or predictive rewriting.


## 1.2.0

- Shared native Mac/Windows formatting for introduced bullet lists, spoken numbered steps and explicit task checkboxes, with original transcripts retained.
- Protect literals within mixed prose instead of disabling formatting for the whole transcript.
- Fix Mac permission indicators overwriting effective grants with helper-process readings; avoid repeated microphone requests when already allowed.
- Prevent Windows WebView2 from persisting temporary microphone denials and recover old website decisions without clearing login or OS consent.
- Expand shared multilingual output and preservation regression fixtures.


## 1.1.1 preview

- Check GitHub releases automatically shortly after launch and every six hours while FlowGPT runs.
- Show a nonactivating Mac update notice or a silent Windows tray notification, including with the main window closed.
- Announce each newer compatible version once per launch; defer checks and notices until dictation finishes.
- Mac notice downloads and opens the verified DMG. Windows notification opens About with verified download/install controls. A fully quit app checks again on its next launch.

## 1.1.0 preview

- Shorter native Home, History, Settings and About interfaces, with update checking and checksum-verified downloads.
- Windows Ctrl + Space option, close-to-tray handling, per-user login startup checks and smoother DPI-aware recording strip.
- Fix the reported Windows value-pattern access violation; isolate text-field automation on a worker thread and guard native/UI callbacks.
- Broader rich-editor capability checks, native foreground paste, and typed clipboard restoration without holding the completion loader open.
- Preserve the original transcript alongside optional whitespace-only numbered-list presentation. No extra AI pass or language rewriting.
- Faster provider polling and completion stability checks that reset when processing resumes or the transcript changes.
- Trusted publisher signing workflows are prepared, but this preview remains unsigned/ad hoc because publisher credentials are not configured.
- Mac PowerPoint canvas focus is still ambiguous; real Windows Office and physical microphone/account testing remain necessary. See the release validation report for measured results and limits.

## 1.0.3

- Capture-only native microphone startup before browser/network initialization.
- Bounded PCM buffering and ordered delivery to ChatGPT's Dictate recorder.
- Idle connection recovery, wake checks, and protection for drafts and active sessions.
- Installed-app diagnostic first audio measured at 57–167 ms over five starts on the development Mac.
- Live recorder startup measured at 382 ms in one check; completed transcription/paste was not established by that cancelled check.

## 1.0.2

- Compact bottom recording strip, real-level waveform, and processing loader.
- Background menu-bar behavior without reopening Settings after completion or errors.
- Audio buffering and built-in microphone preference to reduce Bluetooth disruption.

## 1.0.1

- Native sidebar interface with Overview, History, and Settings.
- Searchable local history and separate permission rows.
- Liquid Glass on supported macOS versions with an earlier-system fallback.

## 1.0.0

- Introduced the FlowGPT name and embedded ChatGPT dictation bridge.
- Persistent WebKit website session, local transcript saving, and focused-field insertion.

## Earlier Flow versions

Retired versions used Groq Whisper and GPT-OSS, formatting prompts, and experimental lecture and language-processing paths. Historical reports remain under `Docs/FLOW_*`; those features are not claims about the current browser bridge.
