# FlowGPT for Windows

The Windows implementation uses C++/WinRT, WinUI 3, WASAPI microphone capture, and an embedded WebView2 ChatGPT session. It follows the current Mac browser-bridge workflow; older Groq and lecture implementations are not part of this Windows app.

## Install and connect

You need Windows 11 on an Intel/AMD 64-bit PC, internet access, and your own ChatGPT account with dictation available. No API key is needed.

1. **[Download FlowGPT for Windows (.exe)](https://github.com/rachitkothadia/FlowGPT/releases/download/windows-v1.1.0-preview/FlowGPT-1.1.0-Windows-x64-Setup.exe).**
2. **Install it.** Double-click the file, follow the installer, then open **FlowGPT** from the Start menu.
3. **Connect ChatGPT.** Click **Connect ChatGPT**, sign in, then close the connection window.
4. **Allow your microphone if recording is blocked.** Open **Windows Settings → Privacy & security → Microphone** and turn on **Microphone access** and **Let desktop apps access your microphone**. Select your input device in FlowGPT Settings if needed.
5. **Dictate.** Click an editable text field, press **Ctrl + Alt + Space**, speak, then press the same shortcut again to finish.

The installer checks Microsoft WebView2 Runtime automatically. This preview is unsigned, so Windows may show an unknown-publisher warning. See [installation help](../README.md#need-help-installing). The [release page](https://github.com/rachitkothadia/FlowGPT/releases/tag/windows-v1.1.0-preview) includes the EXE and its checksum.

Use **Try dictation** to try recording inside FlowGPT. Results are saved in **History**. Your own local ChatGPT profile is reused between launches and ordinary upgrades; expired sessions need sign-in again.

Settings offers **Ctrl + Space**, **Ctrl + Alt + D** and **Ctrl + F8** if another app already owns the default combination. Microphone access is established by actual capture, not a hardcoded green permission indicator. Windows does not use macOS Accessibility/Input Monitoring grants.

## Background operation

Closing the main window keeps FlowGPT in the notification area. Use its tray menu for connection, history/settings, local dictation preview, or Quit. Completion does not activate Settings. The installer selects **Start FlowGPT in the tray when I sign in** by default; you can change this in FlowGPT Settings. It is a per-user desktop app, not a service that records while nobody is signed in.

## Audio and text delivery

Native capture starts independently of browser preparation. The capture path requests 16 kHz mono float PCM using shared-mode WASAPI conversion. Opening speech waits in a bounded memory queue; overflow, device failure, or connection interruption produces an error rather than pretending the transcript is complete. No speaker volume or default device is changed by the app.

The microphone strip shows real levels, becomes a loader when finishing, and hides after completion or failure. Audio is sent to OpenAI through ChatGPT's website. The app reads the unsent composer transcript and stores it before clearing the matching draft. It does not send a ChatGPT message. Optional instant native formatting only adds line breaks around explicit consecutive numbered items. Words, scripts, repetitions, code and quoted text stay unchanged; the original returned transcript stays in History.

Automatic paste revalidates the focused destination and preserves the clipboard where its formats can be safely snapshotted. A new user copy takes precedence over restoring old contents. Unsupported clipboard formats, changed targets, password/read-only controls, and elevated/protected editors can prevent insertion. The transcript remains in History. An attempted paste is not automatically repeated or claimed to be confirmed.

## Local data and updates

Starting with 1.1.1, FlowGPT checks GitHub shortly after launch and every six hours while running. It queues a silent tray notification for a newer compatible release, including with the main window closed. Click it to open About and download/install the update. Each version is announced once per launch, after dictation finishes. Windows notification settings or Do Not Disturb can suppress the notice. A fully quit app resumes checking on its next launch.

Data is under `%LOCALAPPDATA%\FlowGPT\`:

- `history.json`: the latest 100 transcripts, with atomic saving.
- `settings.json`: microphone, shortcut, appearance, and numbered-list presentation.
- `WebView2\`: the connection's browser profile.

The installer never bundles someone's login or transcript history. Upgrade preserves data. Uninstall offers an explicit choice to delete personal data; keeping it allows reinstalling without intentionally clearing it. Local transcripts are not encrypted by this application.

Choose **About → Check for updates**, then **Download update → Install update**. The app verifies the published SHA-256 checksum and rechecks the cached installer before opening it. Installation keeps the existing local data folder. Updates currently include compatible previews. Trusted signing is prepared but still requires the developer’s actual certificate; see [publisher signing](PUBLISHER_SIGNING.md).

## Friend test checklist

- Clean installation and launch on Windows 11 x64 without developer tools.
- Own-account connection, close/reopen, and a full Windows sign-out/sign-in with startup enabled.
- First words included when speaking immediately after the shortcut; long pauses do not stop recording.
- Stop during initialization, repeated presses, cancellation, and no duplicate text.
- Hindi/English/Marathi mixed speech; compare against the returned ChatGPT transcription.
- Microphone choice, unplug/replug, Bluetooth, and unchanged speaker volume.
- Popup near the taskbar on multiple monitors and high-DPI displays; no stolen focus or reopened Settings.
- Insertion into Notepad, Word, browser fields, contenteditable/Electron editors, and refusal after changing focus.
- History search, full text, copy/delete, and restart persistence.
- Clipboard before/after insertion, including making a new copy during delivery.
- Network interruption, expired login, sleep/wake, and a browser draft that must be preserved.
- Upgrade and uninstall, including whether saved user data is kept as chosen.

Use **Copy diagnostics** when reporting a failure. It includes version, state, capture timings/error, connection/shortcut state, and history count; it omits transcript text, account credentials, and cookies. Include reproduction steps and redacted screenshots separately. Never send passwords or browser profiles.

## Verification boundaries

Portable policy tests can run on macOS and Windows. Windows native fixtures use isolated local HTML, synthetic audio, temporary storage, a disposable editor, and window lifecycle checks. They do not establish physical microphone performance or that the real signed-in ChatGPT recorder works hidden. Those checks require the real Windows application with the tester's account and hardware.

See [the current 1.1 verification report](FLOWGPT_11_VALIDATION.md) and [the reported crash diagnosis](WINDOWS_100_CRASH.md). Build evidence and any remaining unverified checks accompany the installer. No 100% speech accuracy, every-editor support, or universal startup-time guarantee is claimed.

## Build on Windows

Install Visual Studio 2022/2026 with Desktop development with C++, a Windows SDK, and C++/WinRT tooling. From a Visual Studio developer terminal:

```powershell
msbuild Windows/FlowGPT.vcxproj /restore /p:Configuration=Release /p:Platform=x64
```

The project automatically merges the framework theme resource indexes for unpackaged WinUI startup. `Windows/out/x64/Release` contains the native app and bundled Windows App SDK runtime. For the distributable installer, use the repository's Windows workflow: it adds the matching native CRT, downloads and verifies Microsoft's WebView2 bootstrapper, runs native/UI fixtures, and packages with Inno Setup 6. It then installs, upgrades, launches, and uninstalls the actual EXE payload. An ordinary development build alone is not the finished release installer.

Portable policy checks do not need Windows:

```sh
cmake -S Windows -B /tmp/flowgpt-core-build
cmake --build /tmp/flowgpt-core-build
ctest --test-dir /tmp/flowgpt-core-build --output-on-failure
```

Third-party components retain their own licenses; see [the Windows notices](../Windows/THIRD_PARTY_NOTICES.md).
