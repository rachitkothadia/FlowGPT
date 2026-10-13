# Flow 2.0 validation

10 October 2026. Version 2.0.0 (4), Apple Silicon, macOS 14 minimum.

## Completed checks

- 70 deterministic tests passed, covering session cancellation, temporary audio deletion, safe insertion, credential persistence and deletion, empty-field rejection, WAV metadata, Marathi request language hints, punctuation filtering and preservation of code indentation.
- Production build passed with warnings treated as errors. The app signature and bundle resources passed verification.
- The installed build was tested, then removed at the user's request. Old staged app bundles and backups were also removed. The source project and fresh DMG were retained.
- The actual installed app's Test API Key button showed HTTP 200 for Whisper Turbo and GPT-OSS 120B. Its masked field was populated from the local saved key. Source contains no Keychain or Security-framework credential calls. The old saved credential item was removed.
- The app-level credential diagnostic verified populated fields after reopening, rejecting an empty test input despite a stored key, and deleting the saved value. It used an isolated fake test key and made no network requests.
- The final installed production binary passed all 13 live formatting fixtures. QA/formatting-results.json records the completed run.
- Synthetic speech requests returned HTTP 200 for English and Hindi using Turbo, and for Marathi using both Turbo and full v3. Marathi audio was read by the Hindi Lekha system voice, so this test proves request compatibility, not native Marathi accuracy. Both Marathi transcripts had errors. Original user audio was unavailable.
- The production popup view was visually inspected in a separate, nonrecording preview app. Native Liquid Glass rendered on macOS 26. The preview was stopped after inspection.
- Flow-2.0.0-arm64.dmg was created and its checksum verified. No user credential is packaged.

## Fresh setup requested by the user

The installed Flow app, saved API key, history, preferences, temporary audio and app backups were removed. Its login service was unregistered. The legacy Keychain credential is absent. macOS permission grants were reset for in.vardaan.flow only. Wispr Flow was left untouched.

The fresh installer contains version 2.0.0 (4), has a verified signature and checksum, and contains no user key. After installation, the user must paste their key and grant Microphone, Accessibility and Input Monitoring permissions to this build.

System Settings had shown the previous Accessibility entry switched on, while macOS logs reported that its saved code requirement did not match the updated local build. The app correctly reported no effective grant. A terminal-launched diagnostic can inherit the caller's permissions and is not evidence that the Finder-launched app can record or insert. End-to-end microphone/shortcut/insertion verification remains for the user's fresh setup; it is not claimed as passed.
