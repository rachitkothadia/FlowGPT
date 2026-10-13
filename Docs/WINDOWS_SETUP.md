# FlowGPT for Windows

The Windows implementation uses C++/WinRT, WinUI 3, WASAPI microphone capture, and an embedded WebView2 ChatGPT session. It follows the current Mac browser-bridge workflow; older Groq and lecture implementations are not part of this Windows app.

## Install and connect

1. Use Windows 11 on an Intel/AMD x64 PC. Download `FlowGPT-1.0.0-Windows-x64-Setup.exe` from the provided test release.
2. Run the installer. It installs the app for your Windows account and checks Microsoft Edge WebView2 Runtime. The first Windows preview is unsigned; Windows trust/reputation warnings are possible. No Mac quarantine command applies to Windows.
3. Open FlowGPT and choose **Continue with ChatGPT / Manage connection**. Sign in yourself, then close that connection window. The saved profile is reused on later launches and ordinary upgrades; expired/revoked sessions require another sign-in.
4. Open Windows microphone privacy from FlowGPT Settings. Enable microphone access for desktop applications if capture is denied. Choose your microphone in FlowGPT.
5. Use **Test dictation here** for a local result saved to History. For another application, focus an editable field and use **Ctrl + Alt + Space**, then press again to finish.

Settings offers alternative shortcuts if another app already owns the combination. Microphone access is established by actual capture, not a hardcoded green permission indicator. Windows does not use macOS Accessibility/Input Monitoring grants.

## Background operation

Closing the main window keeps FlowGPT in the notification area. Use its tray menu for connection, history/settings, local dictation preview, or Quit. Completion does not activate Settings. The installer selects **Start FlowGPT in the tray when I sign in** by default; you can change this in FlowGPT Settings. It is a per-user desktop app, not a service that records while nobody is signed in.

## Audio and text delivery

Native capture starts independently of browser preparation. The capture path requests 16 kHz mono float PCM using shared-mode WASAPI conversion. Opening speech waits in a bounded memory queue; overflow, device failure, or connection interruption produces an error rather than pretending the transcript is complete. No speaker volume or default device is changed by the app.

The microphone strip shows real levels, becomes a loader when finishing, and hides after completion or failure. Audio is sent to OpenAI through ChatGPT's website. The app reads the unsent composer transcript and stores it before clearing the matching draft. It does not send a ChatGPT message or apply an extra formatter.

Automatic paste revalidates the focused destination and preserves the clipboard where its formats can be safely snapshotted. A new user copy takes precedence over restoring old contents. Unsupported clipboard formats, changed targets, password/read-only controls, and elevated/protected editors can prevent insertion. The transcript remains in History. An attempted paste is not automatically repeated or claimed to be confirmed.

## Local data and updates

Data is under `%LOCALAPPDATA%\FlowGPT\`:

- `history.json`: the latest 100 transcripts, with atomic saving.
- `settings.json`: microphone, shortcut, and appearance.
- `WebView2\`: the connection's browser profile.

The installer never bundles someone's login or transcript history. Upgrade preserves data. Uninstall offers an explicit choice to delete personal data; keeping it allows reinstalling without intentionally clearing it. Local transcripts are not encrypted by this application.

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

Build evidence and any remaining unverified checks must accompany the installer. No 100% speech accuracy, every-editor support, or universal startup-time guarantee is claimed.

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
