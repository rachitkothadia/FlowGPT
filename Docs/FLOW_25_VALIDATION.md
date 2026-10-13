# Flow 2.5 validation

10 October 2026. Results distinguish implementation tests, synthetic speech, real hardware and unverified compatibility.

## Deterministic implementation

The final release gate passed 90 tests in nine suites, including the 960 parameterized preservation cases below.

The Swift Testing suite includes prior connection/key/permission policies plus Flow 2.5 Unicode preservation, exact corrections, ambiguity refusal, technical symbols, quantities, informal tone, quotations, SQLite persistence, backward preferences decoding, archive path safety, failure/reopen recovery, silence handling and shutdown checkpoints. Parameterized preservation checks cover 15 script fixtures and 16 sectors, with four rewrite faults each: 960 text cases. They test rejection of corruption, not native speech accuracy in those languages.

The long-session controller test simulates elapsed time of ten hours and verifies that it remains recording beyond the everyday three-minute cutoff. A separate queue test processes 600 synthetic segment files in order and verifies durable completion. These are state/storage tests, not ten hours of API calls.

## Actual API requests

The final live formatting suite passed 20/20 fixtures after the initial 18/20 exposed missing quotation layout and an empty model completion. Exact quotation rules and safe fallback for empty/malformed formatting output address those failures. Inputs include shopping ingredients, Hindi/Marathi lists, informal pronouns, mixed language lecture text, Bengali/Gujarati/Punjabi/Tamil/Telugu/Kannada/Malayalam/Urdu/Odia script preservation, quotations, programming families/operators, negation and numeric units. The Odia case is text preservation only.

The speech suite generated 54 synthetic WAV recordings using six installed macOS voices: English (India), Hindi, Bengali, Tamil, Telugu and Kannada. Three domains (shopping, technical study, meetings) each had normal, fast and quiet variants. Every transcription and formatting request returned HTTP 200 using the same saved key. The formatter preserved the raw transcript in all 54 cases.

**HTTP 200 is not a recognition-accuracy pass.** Mean raw word error rates against the written synthetic reference were:

| Language | Cases | Mean WER |
|---|---:|---:|
| English | 9 | 3.86% |
| Hindi | 9 | 8.91% |
| Bengali | 9 | 78.89% |
| Tamil | 9 | 42.86% |
| Telugu | 9 | 44.07% |
| Kannada | 9 | 54.44% |

WER counts spelling, number representation and transliteration differences as errors and is not a semantic score. Synthetic compact voices may mispronounce mixed English terms, so these results cannot be generalized to human speakers. They do expose a clear limit: this build is not verified for perfect regional-language speech. High-error fixtures are retained, not renamed as successful accuracy tests.

Six matched technical recordings were also transcribed by full Whisper v3. It improved the measured result for Bengali, Tamil and Kannada but did not eliminate their errors; English/Hindi had zero WER in that particular technical sample with both models. A second six-file comparison with broad technical vocabulary hints made four regional-language results worse. Those automatic broad hints were removed. User-approved hints remain available. Both experiment outputs are retained for reproducibility.

Files: `QA/flow25-live-results-final.json`, `QA/flow25-speech/results.json`, `QA/flow25-speech/full-v3-comparison.json`, `QA/flow25-speech/turbo-technical-hints-comparison.json`. Inputs, synthetic WAVs and reference text are retained. Test credentials are not in these files.

## Capture, permissions and insertion

Production PCM writer checks simulated 1, 2, 4 and 10 hours of sample duration. They yielded 60, 120, 240 and 600 segments respectively, with exactly 57,600,000; 115,200,000; 230,400,000; and 576,000,000 frames. No PCM frames were dropped or duplicated by that writer. This did not exercise the physical microphone, resampler or service in real time.

A real three-second continuous microphone test caught a Swift actor-isolation crash in the audio callback. The callback was explicitly made Sendable; a repeat passed, saving 49,597 frames over 3.0998 seconds. This is short hardware validation, not multi-hour endurance.

Permission probes launched from the diagnostic tool returned Microphone=true, Accessibility=true and Input Monitoring=true. The separately launched native Flow 2.5 GUI showed all three as not granted. Tool-context probes therefore do not establish permission for the installed app. The fresh ad hoc build needs its own grants during setup; no TCC reset or forced green indicator was used. Credential diagnostics verified reopening restores the field, an empty entered field clears/refuses a test, and deleting the test credential removes it. These diagnostics use a separate disposable credential file. The actual packaged app's Test API Key button also returned HTTP 200 for both Whisper Turbo and GPT-OSS 120B, with the saved key present in its masked field.

The production insertion code no longer uses clipboard contents. Native editor integration attempts could not establish an active TextEdit target through the current UI automation session; metadata showed a different frontmost app/non-text element, which the production guard correctly refused. **Successful live Accessibility/Unicode insertion and clipboard invariance remain unverified.** Fake insertion tests cover session delivery/cancellation only and are not substituted for that test.

System-audio capture, physical Fn behavior, real 2–10 hour sessions, native-speaker coverage for all Indian languages and broad destination-app insertion require further real-world validation. Sleep/device changes interrupt capture and retain finalized segments; an unfinished crash tail is not automatically repaired.

## Packaging

The release is arm64 for macOS 14+, locally ad hoc signed. It is not notarized. Bundle resources/version, strict signature verification, DMG integrity and a read-only mount passed. The DMG is in the project root; release stores build logs. Saved credentials, phrase memory and recordings are not bundled. The old installed Flow 2.0 bundle was quit and moved to Trash, preserving the local key, settings and phrase data for the user's fresh installation.
