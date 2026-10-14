# FlowGPT 1.1.0 preview validation

Validated on 14 October 2026. This is an experimental ChatGPT website bridge. Software checks are not speech-recognition accuracy scores.

## Deliverables and source

- Mac: `FlowGpt-1.1.0-arm64.dmg`, macOS 14+ on Apple Silicon. Mac source was frozen in commit `267d2b6` and is unchanged by later Windows/documentation commits.
- Windows: `FlowGPT-1.1.0-Windows-x64-Setup.exe`, Windows 11 x64. Final application source: `6dea7c1b70c3d56869a4e063f41c26bd0e09250c`.
- [Final Windows build and installer checks](https://github.com/rachitkothadia/FlowGPT/actions/runs/38544719225).
- Mac DMG SHA-256: `a71c28816de3e29d7f5aee9bd8631afbfdd038b1fb01ec84168bc28a8e334db0`.
- Windows installer SHA-256: `d7e413a3e75d3a59f74ef54a7bb0dc73be96877b064f8a201685112c0a544a44`.
- Each release includes `SHA256SUMS.txt`; the Windows checksum identifies the final installer after packaging.

## Changes verified

| Area | Result |
| --- | --- |
| Mac policies and regressions | 120 tests passed; release build treats warnings as errors. |
| Windows portable policies | 79 checks passed, including audio-tail shutdown ordering, completion stability, formatting and update checksums. |
| Mac browser/audio fixture | 50 checks passed using isolated WebKit HTML and synthetic audio. |
| Mac window lifecycle | 10 checks passed: menu-bar residence, nonactivating bottom strip, no completion reopening, no Dock requirement. |
| Windows native fixtures | 52 checks passed: native editor, RichEdit, clipboard, storage, hidden WebView2 audio and focus races. [Evidence](windows-native-fixtures-11.json). |
| Windows UI lifecycle | 17 checks passed: Home, History search, Settings, About, themes, Ctrl+Space, close-to-tray, reopen and contained presentation failure. [Evidence](windows-ui-fixtures-11.json). |
| Windows installer lifecycle | 11 checks passed: checksum-verified released 1.0 installation, actual 1.0→1.1 upgrade, payload/data preservation, background launch, reinstall and uninstall. [Evidence](windows-installer-fixtures-11.json). |
| Mac package | Strict ad hoc signature verification and DMG integrity verification passed. This is not Developer ID notarization. |

Windows fixtures execute the actual native EXE on a Windows runner. They do not use a mock Windows screenshot or execute the Windows binary on Mac. Test-only storage and browser profiles are not bundled in the installer.

## Actual Mac microphone and Word checks

Five real microphone starts on the final package returned first audio frames in **116–458 ms**. Capture used the built-in microphone, without an account connection, upload, permission reset, or speaker-volume changes. [Raw timing evidence](mac-native-microphone-11.json).

Three tests in a disposable Word document delivered the exact English/Hindi/Marathi fixture text once per test, without loss or duplication. Every original clipboard format was restored. The production adapter returned in **112.8, 23.0 and 24.4 ms**. It honestly reports an attempted dispatch; independent QA verifies actual document content. These are insertion times, not shortcut-to-transcription times. [Package hashes and Word evidence](mac-word-insertion-11.json).

Mac Home, Settings, About, recording waveform and replacement loader were also inspected in the isolated visual preview. Its illustrative connection/permission indicators do not establish an actual signed-in session.

## Root causes and regression coverage

The friend's Windows `0xc0000005` failure was mapped to the exact released EXE and matching PDB: an unchecked value-pattern interface dereference at RVA `0xa03b`. [Matching-binary diagnosis](WINDOWS_100_CRASH.md). Successful provider responses with a null pattern now fail safely; the production adapter regression passed.

Field automation now runs on a windowless MTA worker. Windows validates both raw focused identity and the resolved rich editor, native focus, foreground window, and a shared focus-event epoch. A regression switches between two EDIT controls in the same window during a blocking provider call and verifies neither field receives the transcript. Subscription teardown permits COM callbacks while waiting for the worker, so Quit does not deadlock.

Mac Office can report an enclosing focus proxy and false default flags for attributes it does not advertise. The adapter resolves an unambiguous text caret/editor and uses only declared flags as authoritative. Repeated ancestor/value reads caused avoidable insertion delay; validation reuses its ancestry and dispatch no longer waits for a synchronous full-document confirmation read. Both platforms recheck focus immediately before input and never replay an uncertain paste.

Audio shutdown previously froze the queue before pending capture callbacks could finish. Both platforms now stop the producer, drain its final queued samples, then freeze. The Mac regression reproduces loss with the previous ordering; the Windows regression covers an in-flight packet plus the final pending packet. Browser delivery still waits for accepted audio to drain.

## Conservative formatting

Instant native formatting preserves returned words, order, repetitions, self-corrections, scripts, names, numbers and code. It only adds whitespace around already explicit consecutive numbered items starting at 1. Long-list tests exceed 100 items. It does not infer a shopping list from conversation, insert guessed quotations, change case based on volume, remove uncertain fillers, translate or repair recognition errors. Original text remains available in History.

There is no additional AI request or system prompt sent to ChatGPT Dictate. Its website recorder does not expose that setting. The user's chosen native option avoids a second request but cannot change the provider's recognition accuracy.

## Remaining limits

- PowerPoint on the tested Mac exposes indistinguishable focus information for an active text caret and a selected shape. Ambiguous canvas targets remain refused. Universal PowerPoint support is unresolved.
- Windows Word/PowerPoint, physical microphones, Bluetooth, multi-monitor DPI transitions, real login startup and completed signed-in ChatGPT transcription still need a user-machine check. RichEdit is an actual native fixture, not proof that every Office field works.
- Total stop-to-text latency of 50–200 ms is not established. Provider/network processing, audio drain and a 200 ms stability check remain necessary. No perfect accuracy or multi-hour recording claim is made.
- Mac login registration and window behavior are implemented, but a real logout/login was not performed. Windows installer startup registration and background launch are checked; a full Windows login is not.
- Mac updates verify and open a DMG for manual replacement. Windows verifies and opens the EXE installer. Neither path was tested against a newly published higher-version live update during dictation.
- Trusted Windows signing and Apple notarization remain blocked by missing publisher credentials. Signing workflows are prepared; this Windows preview remains unsigned and this Mac preview ad hoc signed. [Required signing setup](PUBLISHER_SIGNING.md).

Existing installed Mac application, saved connection, history, Accessibility and Input Monitoring settings were left unchanged during isolated packaging and QA.
