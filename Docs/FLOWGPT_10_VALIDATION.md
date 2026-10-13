# FlowGpt 1.0 validation, 13 October 2026

## Passed

- Final native software suite: 105 tests in 13 suites. These verify program behavior, not transcription accuracy.
- Release arm64 build with warnings treated as errors; strict bundle signature validation; verified DMG checksum.
- Existing ChatGPT website login restored after Flow → FlowGpt rename and multiple process restarts without another sign-in.
- Ten production browser-adapter fixture checks passed, including cancellation, draft protection, verbatim mixed-script reads and never-send behavior. These simulate page controls, not speech recognition.
- The real microphone-to-history path returned and saved a transcript unchanged. A generated phrase played through the selected Bluetooth headset output, so that attempt was not a valid known-phrase accuracy benchmark. No broad speech-accuracy claim is made.
- Native clipboard checks passed for multiple items/formats, concurrent copies and restoration of an empty clipboard.
- Live microphone check through the real ChatGPT page, with no simulated transcript: microphone capture stayed active for two seconds, the connection UI was invisible, and destination app focus was preserved. The recording was cancelled afterward; this hardware check did not save a transcript or send a ChatGPT message.
- Old application copies and project installers retired to Trash using an explicit verified bundle-ID manifest. Source, website login, local history, API key and unused NLP history remain.

## Background rendering

Ordering the WebKit window out, or moving it entirely offscreen, failed live microphone startup. The working path keeps a transparent window behind other apps. It cannot become key/main and ignores mouse events while hidden. This is an embedded browser engine running in the app, not OAuth and not a separate ChatGPT app.

The report at release/flowgpt/recording-check.json records passed=true, microphoneActive=true, browserWindowHidden=true and destinationFocusPreserved=true. Its microphone/accessibility/inputMonitoring fields are the **initial** permission snapshot before any microphone authorization request; they are not the final microphone capture result.

## Pending

The new ad hoc signed binary needs refreshed Accessibility and Input Monitoring approval. macOS displays an enabled entry while the runtime still denies those grants because its stored code requirement references the old build. No privacy grant was reset or revoked by cleanup. The user has been asked to approve the final binary through normal System Settings controls.

The user chose to handle macOS grants themselves. No further permission requests or toggles were performed. The final package includes a small preview-button fix: Test dictation here explicitly sets localPreview=true, instead of deriving it from the frontmost app. This prevents assistive/programmatic button activation from attempting insertion elsewhere. The final suite and package were rechecked after that change; live preview/shortcut delivery in that exact build remains subject to the user's grants.

Global Fn + Space, automatic insertion, clipboard restoration in the final GUI, and grant persistence after restart need their final live checks after approval. Earlier Flow software tests and the earlier browser-to-history test do not substitute for these checks.

The commercial Wispr Flow application and its unrelated vendor installer are not our Flow builds and were left untouched. Retired copies remain recoverable in Trash; Trash was not emptied.

## Reproduction

- Scripts/build-flowgpt.sh runs the suite, builds and packages FlowGpt-1.0.0-arm64.dmg in the project root.
- Launch the packaged app with --bridge-recording-check for the real hidden microphone check; result: /tmp/flowgpt-recording-check.json.
- --browser-driver-check runs simulated page-control checks; it is not a speech test.
- --bridge-integration-check runs the ordinary GUI and writes non-transcript state and shortcut counts to /tmp/flowgpt-integration-check.json.

No unlimited usage, permanent account session, cross-version macOS permission persistence or perfect recognition is claimed.
