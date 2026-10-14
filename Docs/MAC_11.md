# FlowGpt 1.1 on Mac

## Start recording

1. Open FlowGpt and connect your own ChatGPT account in Settings.
2. Allow Microphone, Accessibility, and Input Monitoring when macOS asks.
3. Click where you want text to appear. Press **Fn + Space**, speak, then press it again.
4. Find returned text in History if the destination cannot accept insertion.

Closing the window keeps FlowGpt in the menu bar. Choose **Quit FlowGpt** from its menu to exit. **Settings → Start FlowGpt when I log in** enables background login launch using Apple's Service Management. macOS may ask you to approve it in Login Items; FlowGpt never changes another app's permissions.

## Formatting

FlowGpt uses instant native presentation, with no additional AI request. Outside authorized currency amount normalization and filler removal, it preserves returned words, word order, repeated speech, self-corrections, language scripts, names, numbers, technical terms, paths, and quotations. It detects coordinated item phrases and repeated actions without requiring introduction words. Related items use • bullets, procedural actions use numbered lines, and identifiable currency amounts use symbols or currency codes. Clear hesitation sounds can be removed. It does not guess lists from conversation, guess quotations, translate, rewrite grammar, or uppercase loud speech. Ambiguous fillers remain unchanged. Quoted text, code, URLs, and paths retain their literal content, even within a formatted list.

History retains both the original returned transcript and the displayed version. **Copy original** appears whenever presentation differs. This preserves the transcription provider's output; FlowGpt cannot guarantee that provider recognized every spoken word correctly.

## Updates

Starting with 1.1.1, FlowGpt checks GitHub shortly after launch and every six hours while it runs. A small notice appears without taking keyboard focus, even when the main window is closed. Choose **Download update** or **Later**. Each available version is announced once per launch, after any active dictation finishes. Fully quitting the menu-bar app stops checks; they resume on the next launch.

Choose **About → Check for updates**. FlowGpt checks this repository's published releases, including previews, for a newer DMG compatible with your Mac. **Download & open installer** verifies the published SHA-256 checksum before opening the installer. Quit FlowGpt, then replace the application in Applications. Connection and history stay in the existing application-support folder. Permission refresh may still be required when the application's signing identity changes. This preview does not silently replace the app or bypass Gatekeeper; automatic signed installation is not enabled without the developer's real signing/notarization credentials.

Checksums detect corruption or a mismatched release download. They do not replace publisher signing. Developer ID signing and Apple notarization require the developer's real Apple credentials. The distribution script refuses to claim a signed/notarized release without them; local preview builds remain ad hoc signed and Gatekeeper may warn.

## What was changed

- Home is shorter, with one recording action and the latest transcript. History, Settings, and About remain easy to reach.
- Rich editors can advertise a caret/text range without a writable whole-document value. Word can return a false enabled value for an attribute it does not actually advertise; only advertised flags are authoritative. Explicitly disabled fields, passwords, read-only fields, and changed targets still block insertion.
- A native foreground keyboard paste handles editors that do not accept accessibility text writes. Dispatch returns promptly as an attempted paste, without blocking on a synchronous read of the destination. Clipboard restoration happens separately after 700 ms, and any newer user copy wins. Quitting waits for that restoration. FlowGpt never overwrites the entire document or retries an uncertain paste. Three independent Word checks confirmed exact mixed-language delivery and clipboard restoration, with adapter return times of 23.0–112.8 ms; these are insertion times, not total transcription latency.
- Completion requires the provider's ready state, no active recording/transcription, and unchanged text for 200 ms. Polling is 50 ms instead of 150 ms. Audio drain and provider completion are still required; internet/ChatGPT processing time cannot be guaranteed at 50–200 ms.
- The small nonactivating recording strip stays at the usable bottom edge and disappears after completion without reopening the main window.

## Verification limits

Automated tests cover preservation, numbered-list limits, rich-editor capability gates, focus/security policies, completion timing, compatible release selection, and checksum rejection. Isolated preview/window fixtures do not sign in, capture speech, alter installed FlowGpt, or change privacy permissions.

A disposable native Word document received and confirmed the complete English/Hindi/Marathi test payload through the production insertion adapter, and the original clipboard was restored. Native PowerPoint exposes the same focus proxy and range-mutation marker for both an active text caret and a selected shape. This build refuses that ambiguous target rather than creating a new text box unexpectedly. Universal PowerPoint insertion remains unresolved on this Mac. Actual microphone/ChatGPT transcription, signed release update installation, and login startup still need authorized user-machine checks.


For 1.2 permission and formatting details, see [the release notes](FLOWGPT_12.md). Indicators now use the running app’s actual grants. Idle ChatGPT pages do not show another microphone prompt. A new ad hoc preview build may still need renewed macOS grants after installation; a stable Developer ID certificate is needed across upgrades.


[FlowGPT 1.3 changes and verification](https://github.com/rachitkothadia/FlowGPT/blob/main/Docs/FLOWGPT_13.md).
