# Changelog

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
