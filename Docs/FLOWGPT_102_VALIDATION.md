# FlowGpt 1.0.2 recording and window changes

## Behavior

- Temporary Chat is prepared during connection loading rather than inside every shortcut start.
- Local WebKit microphone capture feeds a bounded 30-second mono audio FIFO while the ChatGPT recorder initializes. Once its recording UI and buffered stream attachment are acknowledged, samples play into its MediaRecorder in original order. The audio graph is never connected to the speakers.
- Stop freezes the microphone immediately, drains remaining audio, then stops ChatGPT dictation. Pressing the shortcut during startup queues the stop instead of ignoring it.
- The browser prefers a labelled MacBook/built-in microphone with an exact device constraint. This avoids a Bluetooth headset microphone route when that input is available. Hidden device labels/other machines use the system default. The app neither synthesizes volume keys nor calls a system volume setter.
- Recording bars show measured input RMS, not a repeating symbol animation. The mic becomes a loader after stopping.
- The visible strip is 104×32 points inside a 116×44-point nonactivating panel, positioned 2 points above the usable display's bottom edge. Dock avoidance remains in effect.
- Success, unverified insertion, errors and cancellation hide the strip without reopening Settings. Status stays in the menu bar/history. Settings no longer offers a minimize-to-Dock action; the app remains an accessory/menu-bar app.

## Verified

- 107 native software tests in 13 suites passed, including new stop-during-startup and cancellation-during-startup regression tests. These are software tests, not an audio accuracy score.
- 30 WebKit fixture checks passed on three consecutive runs. Ten cover DOM/draft protection; ten each exercise the normal audio processor and forced compatibility fallback: audio FIFO ordering, stopping, overflow, real synthetic audio levels, preferred device constraints, a single getUserMedia acquisition, Web Audio → MediaRecorder delivery, absence of speaker playback, draining and resource cleanup. Recorded audio is decoded and its RMS verified, rather than only checking that encoded bytes exist. Synthetic input is used; no user microphone or live account is involved. An earlier intermittent fixture failure was resolved by retaining the simulated media-device wrapper between native evaluations and waiting for the synthetic signal to arrive rather than inspecting its first silent quantum.
- Ten native window fixture checks passed: accessory activation policy, closed-settings residency, nonactivating strip, compact dimensions, usable-bottom position, and no settings reopening after success/error/attempted/cancelled results.
- Native visual preview: smaller mic/level bars and mic-to-loader replacement inspected and captured. Preview history and level values are fixtures; screenshots do not show real transcription or actual permission grants.
- Final DMG mounted read-only; its executable and bundled guide match the staged release/source guide. Strict local signature verification passed, and the image was detached.

Evidence is in `QA/FlowGpt-1.0.2/`, `QA/FlowGpt-UI/*-102.png` and `release/flowgpt/`.

## Not verified live

The packaged live microphone check stopped before requesting capture: macOS reported microphone permission unavailable for this rebuilt ad hoc signature. It deliberately did not request/change Microphone, Accessibility or Input Monitoring. User-managed authorization is required for the rebuilt installed app.

Consequently this release has no confirmed real ChatGPT startup timing, microphone-to-transcript test, Bluetooth output-volume stability test, or global Fn+Space-to-paste test. Preferring the built-in input is a mitigation for Bluetooth profile switching, not evidence that the user's volume jump has been reproduced and resolved. Initial microphone/AudioContext initialization can still delay the first samples, and draining startup audio can extend processing. Website-side changes, CSP/worklet restrictions and network delay remain possible. AudioWorklet is preferred; the same FIFO uses ScriptProcessor compatibility fallback if the worklet is unavailable or blocked.

Installed `/Applications/FlowGpt.app` was left unchanged during verification. The new installer is `FlowGpt-1.0.2-arm64.dmg` directly in the project root. Account data and history were preserved. No TCC reset, signing identity replacement or permission toggles were performed.
