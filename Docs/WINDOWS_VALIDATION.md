# FlowGPT Windows 1.0.0 preview verification

Verified on 14 October 2026. The delivered installer was built from commit `8a9f3c4314ef91f97f8d69bf20b07616f3dcc719` by [this successful Windows run](https://github.com/rachitkothadia/FlowGPT/actions/runs/38479882836). Subsequent documentation and screenshot-capture changes do not change the native application sources.

The runner uses Windows Server 2025 with an interactive desktop. This establishes Windows compilation and controlled native behavior; it is not a physical Windows 11 microphone/account test.

## Delivered file

`FlowGPT-1.0.0-Windows-x64-Setup.exe`, 19,296,337 bytes.

SHA-256:

```text
99a498b1d863c3f598d5ab3dba8d54a43b5fd54bd5124c94513be0d0fde004f7
```

The downloaded installer was checked against the checksum produced by the Windows build. The installer is an Inno Setup launcher containing the x64 native app and its runtime files. The launcher itself is PE32; that does not make the packaged app an x86 app. This preview is unsigned. Microsoft signs its WebView2 bootstrapper, which the build separately verified before use.

## Checks performed

| Area | Result | What was checked |
| --- | --- | --- |
| Portable C++ policies | 47 checks passed in one CTest suite, on macOS and Windows | Session transitions, cancellation generations, retry protection, target identity, Unicode/NUL/size limits, base64, queue ordering, bounds, acknowledgements, and batched delivery. |
| Native Windows fixtures | 41 checks passed | Real file persistence, corrupt-file preservation, hotkey registration, UI Automation and keyboard paste into a disposable native editor, mixed-script text, clipboard restoration, a newer user copy, popup behavior, hidden WebView2 audio, and profile data after reconnect. |
| WinUI lifecycle | 11 checks passed | Visible native window, loaded history, registered shortcut, actual History/Settings pages, case-insensitive and empty search states after UI events, requested themes, close-to-tray, and reopening. |
| Installer lifecycle | 9 checks passed | Install, payload identity, excluded developer reports, login startup registration, installed tray-only launch, upgrade data preservation, uninstall, startup removal, and keeping user data by default. |
| C++ memory/undefined behavior instrumentation | Passed | The portable suite also ran with AddressSanitizer and UndefinedBehaviorSanitizer on the development Mac. |

These checks verify software policies, transport, storage, and UI behavior. Speech accuracy was not tested. The installed application also ran the UI lifecycle fixture from its actual installation directory.

## Audio evidence

The hidden browser fixture recorded a one-second, 440 Hz PCM signal through the actual Web Audio/MediaRecorder path. It received native-style 10 ms packets in ordered batches, drained them before stopping, decoded the recording, and checked signal energy and duration. The decoded recording measured approximately 1.20 seconds including framing/tail time, with energy `0.04482` against input energy `0.045`.

A separate accelerated test simulated six minutes of 10 ms capture packets forwarded on a 100 ms UI schedule. Pending native audio returned to zero on each scheduled delivery. This caught and fixed forwarding only one small capture packet per timer tick. The production path now batches packets and continues delivery after each acknowledgement.

The fixture's returned Hindi/English/Marathi text is predefined. It checks text transport and clearing the matching draft; it does not prove speech recognition accuracy. No physical microphone or real signed-in ChatGPT transcription participated in these automated checks.

## Problems found and fixed

- Native toolchain/projection configuration and required C++/WinRT headers.
- WinUI control metadata and theme-resource packaging needed for real application startup.
- Hidden audio startup awaiting a browser gesture; explicit audio startup now works in the isolated WebView2 fixture.
- Audio acknowledgements arriving before samples were accepted by the renderer.
- Capture packets accumulating faster than the UI timer forwarded them.
- Clipboard sequence changes at completed publication preventing restoration.
- Stale browser callbacks after reconnect or shutdown.
- Search checks running before the native UI updated, and history text areas that were too short.
- Screen bounds, installed payload checks, tray-only startup, and upgrade/uninstall data handling.

The full native build still emits SDK packaging warnings about a metadata reference and duplicate auto-initializer objects. The application linked, launched, and passed the checks above; this report does not claim a warning-free SDK build.

## Checks still requiring the friend's PC

- Actual microphone capture timing, speech quality, beginning/end completeness, pauses, USB/Bluetooth and unplug/replug behavior, and speaker volume.
- Actual ChatGPT sign-in, a completed hidden transcription, session reuse after quitting/reopening, session expiry, and real network interruption.
- Insertion in the friend's browser, Word, Electron/Codex and other editors, with their clipboard formats and focus changes.
- Actual Windows sign-out/sign-in, sleep/wake, monitor/DPI changes, dark/light appearance, and extended background use.
- Long recording limits and multi-hour lectures. The current browser bridge has no validated multi-hour segmentation/recovery system.

Follow [the friend checklist](WINDOWS_SETUP.md#friend-test-checklist). Send reproduction steps and FlowGPT's redacted diagnostics for failures. The installed Mac application, its permissions, profile, and source capture/insertion paths were not changed for this Windows port.
