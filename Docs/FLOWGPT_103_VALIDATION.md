# FlowGpt 1.0.3 startup and connection recovery

## Implementation

The shortcut starts native Swift microphone capture before any browser or network wait. AVCaptureSession selects the built-in input where available and AVCaptureAudioDataOutput delivers 16 kHz mono float PCM. It holds up to 30 seconds of unsent audio in memory. It does not change the system default microphone or output volume and opens no audio output graph. A dedicated serial capture queue copies samples and measures levels with bounded memory.

An independent task prepares the existing ChatGPT Temporary Chat and its recorder. Native frames feed a Web Audio FIFO through the injected public browser controls, with AudioWorklet preferred and a compatible processor fallback. No speech API or private endpoint is called. Stop freezes native capture, delivers all queued frames, drains the browser audio, then asks ChatGPT to transcribe. Metering reads native samples independently of browser polling.

An idle watchdog rechecks the connection every three seconds, with a load/hydration grace period and bounded retry delays. It reconnects after transport or renderer failures, ignores cancelled navigations, and checks after waking. It preserves detected drafts and does not reload active recordings or login pages. Expired/revoked accounts require the user to sign in again; persistent storage does not promise permanent authentication.

## Baseline and live timing

The installed 1.0.2 live warm check captured locally in 261.98 ms and ChatGPT's recorder acknowledged startup in 1,382.77 ms. That single warm check did not reproduce the reported intermittent ten-second start.

The first AVAudioEngine timing check exposed a defect: the engine started in 128.69–537.16 ms across five runs but no first audio frame arrived during the check. These results were failures, not proof of subsecond recording. Routing through a muted mixer then exposed an audio-output initialization error (-10875). The final implementation therefore uses a capture-only AVCaptureSession, avoiding output hardware entirely.

The final capture-only code passed a real hardware benchmark on this Mac's built-in MacBook Air microphone. First PCM frame: 378.51 ms cold, then 112.24, 112.25, 111.48 and 111.39 ms. Capture initialization: 355.01 ms cold, then 100.42–101.54 ms. Every run delivered positive bytes of the validated 16 kHz mono float format with no capture error and was below one second. This was the app's bundled diagnostic executable launched from the terminal, so it establishes hardware/capture-code timing, not the full global shortcut/UI path or macOS authorization of a separate GUI launch.

The installed app's normal LaunchServices path then passed five real microphone starts: first PCM frame 167.13, 56.82, 69.90, 71.14 and 68.79 ms; capture initialization 155.56, 45.84, 59.30, 60.70 and 57.97 ms. All had positive captured PCM bytes and no capture failure. The live signed-in ChatGPT bridge check passed: native capture 128.14 ms, first frame 140.41 ms, ChatGPT recorder acknowledgement 381.53 ms, hidden browser window and destination focus preserved. System output device and volume remained unchanged during that check (volume was already zero). This check cancels recording; it does not measure final transcription accuracy, completed paste or long-term live network recovery.

## Software and synthetic checks

- 110 native software tests in 14 suites passed, including bounded recovery backoff, protecting capture/login/drafts, and ignoring expected cancelled navigation.
- 50 WebKit fixture checks passed: existing DOM/draft behavior, browser and native PCM feeds with both normal AudioWorklet and forced processor fallback, FIFO sample order, overflow/stop/draining, decoded recorded signal RMS, no browser microphone acquisition for native feed, and cleanup.
- Six production connection-manager fixture checks passed with nonpersistent local WebKit data: initial readiness, ignored cancellation, renderer interruption reload/recovery, preserved draft, draft blocking reload, and expired login not causing a reload loop. Renderer interruption is simulated through the delegate and unavailable DOM; it is not a real killed browser process or a live network outage.
- Ten native window lifecycle checks passed: compact nonactivating bottom strip, accessory/menu-bar policy, no reopening settings after completion/error/attempted/cancelled results.

Evidence is under `QA/FlowGpt-1.0.3/` and `release/flowgpt/`. Software/fixture counts are not speech accuracy scores.

## Distribution and permissions

FlowGpt 1.0.3 is installed in Applications. Its saved login/history were preserved. The installer is `FlowGpt-1.0.3-arm64.dmg` directly in the project root. This build is ad hoc signed, not notarized; rebuilding can invalidate macOS's existing permission decision. Only the user refreshes permissions. No TCC resets, permission toggles or authentication actions were performed by the agent. The 1.0.2 app is retained under project-owned `release/rollback/` for recovery.

Thirty stale LaunchServices registrations (old installers, Trash and project test/backup apps) were unregistered without deleting those files or changing TCC. The final Applications copy was registered. The old running process was fully stopped before the final update so tests used the current executable. Do not open project QA/staging app bundles as a substitute for the installed app; that can create duplicate registrations again.

The final live bridge check reported Microphone authorized, but Accessibility and Input Monitoring denied for the current signature. The user explicitly elected to finish those grants themselves. Global Fn+Space and final cross-app insertion are therefore not claimed as live-verified for this release. No further source or package rebuild was made after the verified capture-only build.

The subsecond results above are measurements on this Mac, not a universal latency guarantee. Global Fn+Space/paste remains user-permission dependent. ChatGPT recorder/transcription/network time remains separate from local microphone startup and can exceed one second. Actual sleep/network outage recovery over hours has not been tested; the connection-manager fixtures cover the specified deterministic recovery paths only.
