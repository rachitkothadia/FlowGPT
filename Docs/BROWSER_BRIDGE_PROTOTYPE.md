# Flow 5.0 browser bridge prototype

This experimental native Swift app uses ChatGPT's visible dictation UI. It is a separate packaged entry point in the existing Flow executable. The 4.0.2 installer remains available for rollback. No Groq transcription or GPT-OSS formatting is called in bridge mode.

## Operation

1. Open Flow and choose Continue with ChatGPT. Sign in yourself in the connection window; Flow does not receive a password or export browser credentials.
2. Leave that browser window open. Its WebKit website session persists locally. The sign-in performed in Codex's in-app browser is a different session and cannot be transferred to this app.
3. Put the cursor in the destination app and press Fn + Space. Flow captures the destination before operating its background browser window. macOS microphone approval is required; Flow delegates audio to the main ChatGPT page only during an explicitly started Flow recording, and denies camera/other-origin capture. Manual dictation clicks in the connection window still prompt normally.
4. It requires an empty composer and verifies Temporary Chat through the visible Turn off temporary chat control. It clicks Dictate and waits for actual Stop dictation / Cancel dictation controls before reporting recording.
5. Press the shortcut again, or click the HUD microphone. Flow clicks Stop dictation, waits for dictation to return and the composer text to stabilize, then reads the full composer text. If the user instead stops from ChatGPT's own window, Flow detects that and accepts the returned text automatically. It never clicks Send, Transcribe and send, or Start Voice.
6. The transcript is saved locally before removing the matching unsent draft or attempting insertion. Insertion uses the existing native service and clipboard restoration. Starting inside Flow provides a local preview.

Temporary Chat excludes the chat from the sidebar; it does not guarantee zero OpenAI retention. ChatGPT receives microphone audio and account usage restrictions remain. Browser draft removal is not a server-side deletion guarantee.

## Data and failure behavior

- Browser history is separate from old history at `~/Library/Application Support/Flow/browser-history-v1.json`, retaining the latest 100 entries. It is private local, unencrypted JSON. There is no transcript translation, formatter, learned correction or local NLP.
- A non-empty composer is never overwritten at start. A draft changed before cleanup is kept. Failure to save history prevents draft cleanup and insertion, so the browser text is still available.
- A cancelled/stale request cannot create a second insertion. Empty speech, missing controls, sign-out, navigation failures or timeouts report an error without secretly changing speech providers.
- Closing/reloading the browser while recording can interrupt capture. Short microphone dictation only; this prototype does not provide continuous lecture capture or automatic speech-end detection.
- ChatGPT may limit availability or reject an embedded browser/sign-in provider. Flow does not bypass login challenges, CAPTCHA, rate limits, TLS checks, or authentication. The user must resolve normal account prompts in the browser.
- No macOS permission resets, automatic Accessibility/Input Monitoring grant changes, old history removal, API-key removal or installed app replacement are performed by packaging.
- Prototype HUD shows a microphone and static waveform while recording, then a loader. It is not a live volume meter.

## Verification

Live browser observations on 2026-10-13 used a signed-in ChatGPT Temporary Chat:

- Dictate returned `Hello mic testing mic testing 1 2 3 4.` to the unsent composer.
- A second automated Dictate → Stop dictation sequence returned `Hello, hello, just testing.`. No message was sent; the composer text was readable.

Native packaged-app observations on the same date:

- The user completed Google/ChatGPT sign-in in Flow's actual embedded WebKit window. The login persisted across prototype restarts.
- Direct native browser dictation returned a spoken test transcript. The first background start exposed an initial website microphone permission problem. The final driver requires OS microphone authorization and delegates only explicit owned capture to the main HTTPS ChatGPT page.
- The final native app started capture, accepted stopping through ChatGPT's own Stop dictation button, retrieved the user's spoken words verbatim, saved them through the real history store and showed `Transcript saved in Flow`. The resulting history file had mode 0600. No model-response mock participated in this test.
- Earlier tests exposed failure to accept an already-finished browser recording. The driver now accepts returned/transcribing state, and a recording-only monitor finishes the owned session when the browser stop control is used.
- **105 native software tests in 13 suites passed.** **10 real WebKit DOM fixture assertions passed** separately. The latter simulate page controls, not speech recognition. Error recovery also releases browser ownership so empty speech or failed draft cleanup does not prevent the next recording.
- **Fn + Space and cross-app insertion remain unverified in the prototype.** Its runtime permission indicators reported Accessibility and Input Monitoring unavailable. Test launches used `--bridge-no-shortcut` to avoid duplicate shortcut listeners alongside the old Flow. No existing grants were reset or changed.

The live native test establishes one microphone-to-local-history path, not broad language accuracy, global shortcut availability, cross-app insertion or unlimited use. Installing this ad hoc signed prototype may require user approval of its macOS grants.

Native session tests exercise persistence-before-cleanup, draft recovery, exact mixed-script text, local preview, no duplicate sessions, cancellation, empty speech and insertion/browser failures. Separate real WebKit fixture checks exercise the exact DOM adapter, temporary-chat verification, recording acknowledgements, verbatim reads, changed/existing draft protection, cleanup, cancellation and never-send behavior. Fixture checks are simulated page controls and do not measure live transcription accuracy.

## Build and install

`Scripts/build-browser-bridge.sh` builds/tests an arm64 prototype, signs it locally and creates `Flow-5.0.0-browser-prototype-arm64.dmg` in the project root. The bundle retains `in.vardaan.flow`; macOS may reassess an ad hoc signed update. It is not Developer ID signed or notarized.

Quit the old Flow before launching this version, so two apps do not capture the same shortcut. Installation and account sign-in remain user setup steps. The bridge does not promise unlimited free usage, permanent UI compatibility or perfect recognition.
