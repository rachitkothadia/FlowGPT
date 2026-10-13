# Historical Flow 1.x validation

This file records earlier releases. For current Flow 2.0 checks, see FLOW_2_VALIDATION.md.

# Flow 1.0.2 validation and fresh installation

10 October 2026. Installed at /Applications/Flow.app after removing old app copies, old DMGs, preferences, history/cache locations, temporary audio, build binaries and app-specific permissions. Keychain had no saved key. Final test permissions were reset again; app starts with all permissions ungranted and API key empty. Source and latest installer retained.

Changes: large Flow name and icon; fixed sidebar button outside split view; visible bordered secure Groq input in Get Started and Connection, Test API Key beneath it; separate Whisper and GPT-OSS 120B results requiring exact HTTP 200 from actual inference requests; bundled synthetic speech sample; observed permission refresh and independent read-only registration attempt; fresh subprocess for cached Core Graphics permission checks; graceful Restart Flow; styled drag-to-Applications DMG with saved Finder icon positions/background.

Validation: 63 Swift Testing cases passed, release compiler warnings treated as errors. New tests exercise actual POST endpoint/model/audio construction, exact 200 requirement, rejection of 201/204/redirect/auth/rate-limit/server responses, no retry, network failure and cancellation. Live Groq calls remain untested because the user chose to enter the API key themselves. UI correctly shows both models Not tested. No successful model access is claimed.

Input Monitoring was explicitly added through the system + picker after CGRequestListenEventAccess did not create a row. macOS required Touch ID/password and displayed its first-grant quit/reopen notice. With Flow PID 78129 unchanged, grant changed the in-app icon to Granted; revocation changed it back to Not granted. With final installed Flow PID 78808 unchanged, Accessibility grant/revocation updated the icons without manual checks or restarting. Public Core Graphics may also authorize keyboard monitoring through Accessibility; the UI explains this. Restart Flow was tested: PID changed to 78947 and Settings reopened. This does not bypass OS requirements.

The final installed executable and readonly DMG executable have identical SHA-256: ca5d253837fc6af73cad846cfbc8202b049f412b3d6c12fffc81f2e67fa1a8d3. Both signatures verified strictly. DMG checksum passed; release/SHA256SUMS.txt records the installer checksum. Designer window was visually inspected. It contains Flow.app and Applications symlink plus hidden background and Finder layout metadata. Screenshot evidence is under release/.

The app remains locally ad hoc signed; no Developer ID identity was available. Physical Fn shortcut and live full dictation still require user permission grants and key entry.

---

Earlier validation follows as historical evidence; earlier installation/artifact paths may have been removed or superseded.

# Flow 1.0.1 update and clean uninstall

10 October 2026. Sidebar toggle now lives in a fixed header beside Flow, outside the collapsing NavigationSplitView. Removed the automatic toolbar toggle. Visually checked expanded, collapsed and expanded again: button stays at the top left and the sidebar returns normally. Screenshots: release/sidebar-expanded.png and release/sidebar-collapsed.png.

All 58 tests passed again. Release build uses warnings as errors. Fresh DMG: release/Flow-1.0.1-arm64.dmg, version 1.0.1 (2), locally signed. DMG checksum and mounted app signature passed. See release/SHA256SUMS.txt for the current checksum.

At the user's request, Flow was quit and uninstalled. Removed installed and staged app bundles, compiled build copies, the QA helper executable, old DMG, preferences and temporary audio folder. No Keychain key existed. Start at Login was confirmed Off. All app-specific TCC records were reset successfully; System Settings showed no Flow entry in Microphone, Accessibility or Input Monitoring. Source, test logs and fresh DMG are retained for reinstall. The app is not installed or running.

The earlier results below describe the original release before the requested uninstall. Live microphone/Groq/Fn acceptance is still pending a fresh install with permissions and an API key.

---

# Flow 1.0.0 release validation

Date: 10 October 2026 (Asia/Kolkata). Target inspected: Apple M4, arm64, macOS 26.5.1 (25F80). Swift 6.3.3, Command Line Tools macOS SDK. Deployment target: macOS 14.0. No full Xcode or valid Developer ID signing identity was installed.

**Status: built, locally signed, packaged, installed and launch-tested. Live dictation acceptance is pending the user's macOS permission grants and Groq key.** This is a local-use release, not a notarized public distribution.

## Artifacts

- Source: `/Users/rachitkothadia/Projects/Wispr Flow Clone/`
- Reproducible build: `Package.swift`, `Scripts/build-release.sh`, `Scripts/package-dmg.sh`
- App: `/Users/rachitkothadia/Projects/Wispr Flow Clone/release/Flow.app`
- DMG: `/Users/rachitkothadia/Projects/Wispr Flow Clone/release/Flow-1.0.0-arm64.dmg`
- Installed app: `/Applications/Flow.app`
- DMG SHA-256: `bad776868759368d6e45d9002ace78afaf15c36517d0a202261c5ca1a461a14a`

## Build, static checks and packaging

| Check | Actual result |
|---|---|
| Native debug build | Passed |
| Release arm64 build | Passed with compiler warnings treated as errors |
| Swift concurrency/type checking | Passed under Swift 6 |
| Architecture | `file` reported Mach-O 64-bit arm64 |
| Bundle identifier/version | `in.vardaan.flow`, 1.0.0 (1) |
| Resource packaging | Info.plist, microphone usage, icon and bundled guide present |
| Runtime dependencies | System Apple frameworks/Swift libraries; no Testing framework or development server required |
| Local signature | `codesign --verify --strict` passed for release, installed app and mounted DMG app |
| Hardened runtime | Enabled; necessary audio-input entitlement present; unsandboxed for cross-app accessibility |
| Developer ID/notarization | Unavailable; ad hoc signing only; not notarized |
| Gatekeeper assessment | Rejected, as expected for this ad hoc local build; no security settings were bypassed |
| DMG checksum | `hdiutil verify` passed |
| Mounted DMG contents | Exactly Flow.app, Applications link and Install Flow.txt |
| Credential inspection | No environment Groq key or matching Keychain item found; no credential pattern embedded in release binary |
| Source work preserved | Original SKILL.md retained; starting directory had no code and was not a Git repository |

## White-box automated tests

**58 tests in 3 suites passed**, using Apple's Swift Testing framework. The equivalent XCTest suite is supplied in `Tests/XCTest`; XCTest execution was unavailable because Command Line Tools lacks that framework. `Scripts/test.sh` resolves the locally bundled Swift Testing framework and its interop library. Ordinary tests use no network or real API key.

Covered: request endpoint/model/authentication/multipart construction; multilingual transcript parsing; empty/malformed/truncated/reasoning-contaminated response rejection; distinct mode prompts; raw-mode bypass; missing and invalid credentials; 429 bounded retry and long Retry-After refusal; service/redirect/unsupported-input responses; DNS/network/timeout/cancellation; model-list connection checks; recording state transitions; rapid-toggle/session deduplication; cancellation during starting, recording, transcription and generation; late noncooperative responses; termination waiting for audio cleanup; maximum duration; raw-text routing; cleanup-failure recovery; changed-target failure and safe retry; attempted-vs-confirmed insertion state; preference validation and persistence; corruption reporting; opt-in history capacity and permissions; shortcut matching, repeat/release deduplication and reset; clipboard change-count safeguards; login configuration idempotence.

Coverage was collected, as supporting evidence rather than a correctness claim: FlowCore Models and Persistence 100% line coverage, GroqClient 81.1%, SessionController 99.3%. Native OS adapters are additionally assessed below; unit coverage does not establish real microphone or global Fn behavior.

The initial suite exposed a CRLF credential-validation defect. It was corrected using Unicode control-character rejection, and the relevant test and final suite passed. The initial test-toolchain failures (missing XCTest, framework path and interop path) were investigated; the final test script runs successfully on this machine.

Logs: `release/automated-tests.log`, `release/release-tests.log`, `release/release-build.log`, `release/packaging.log`, `release/dmg-validation.log`.

## Black-box installed-app tests

- Installed final release into `/Applications` and launched through Launch Services.
- Inspected actual rendered Settings in light and dark appearances at ordinary window size. Native layout, scrolling, sidebar navigation, permission-denied messaging and labels were visible.
- Start at Login successfully changed from Off to Enabled and back to Off through the actual installed app. It was left Off. An actual reboot/login cycle was not performed.
- Closed Settings and independently verified Flow remained running with **zero ordinary windows**. Evidence: `release/background-lifecycle.log`.
- Verified the standard Settings keyboard command and Quit command in the final installed build. After Command-Q, the Flow process exited. Relaunched successfully; the app did not resume recording or insert text.
- Final installed app displays Microphone, Accessibility and Input Monitoring as **not granted** and offers separate grant/recheck controls. The shortcut is disabled with a visible actionable explanation.
- Finder-installed behavior was distinguished from command-line helper permissions. The build process inherited broader automation permissions, so CLI permission flags were removed from the structural self-check to avoid implying the installed app had those grants.

## Grey-box real cross-application tests

A separate QA executable, `Scripts/InsertionProbe.swift`, was compiled against the actual production `InsertionService.swift` and FlowCore. It exercises the production adapter in external apps with a fixed harmless string. It is **not bundled in the DMG**, and these tests do not establish the installed app's complete microphone-to-Groq-to-insertion workflow. The helper ran under the development/automation process's existing accessibility permissions.

| External test | Observed result |
|---|---|
| TextEdit local plain document, Accessibility insertion | Text appeared; adapter reported confirmed; clipboard string preserved |
| TextEdit same document, forced paste route | Text appeared; adapter reported confirmed; clipboard string preserved |
| Safari local HTML textarea, normal route after fix | Text appeared; adapter reported confirmed; clipboard string preserved |
| Safari local contenteditable rich editor, paste route | Text appeared; adapter reported confirmed; clipboard string preserved |
| Safari password field | Refused as secure; no insertion |
| Focus changed to another field while insertion waited | Refused as destination changed; no insertion |

The first Safari textarea test discovered WebKit acknowledging a selected-text write without changing the input. The implementation now uses paste for web content and reserves direct Accessibility insertion for observable native fields. The textarea was retested successfully. No email/message was sent, no form submitted and no terminal command dictated or executed. Test documents are local files under release/.

Evidence: `release/textedit-insertion.log`, `release/textedit-paste.log`, `release/safari-plain-insertion.log`, `release/safari-rich-insertion.log`, `release/secure-field-refusal.log`, `release/focus-change-refusal.log`, and observed external accessibility trees/screenshots. The early focus-change experiment was repeated after separating helper compilation from execution, so the final refusal test actually changed focus during the pending operation.

## Live API and remaining acceptance tests

**Live Groq transcription and generation: not tested.** No Groq key was available in `GROQ_API_KEY` or inspected matching Keychain services. Mocked HTTP tests are not claimed as live API success.

**Installed-app microphone recording, physical Fn + Space, real fallback shortcut capture, audio waveform, panel behavior during recording/processing, complete live pipeline and installed-app automatic external insertion: not tested.** The installed app has no permission grants and no key. Insertion service tests above are explicitly separate.

Also not performed: Gmail, WhatsApp, Google Meet, Slack, Pages, Notes, terminal or code-editor insertion; multi-display/Spaces tests; real sleep/wake testing; VoiceOver and system Reduce Motion/Reduce Transparency sessions; permission revocation mid-recording; real login/reboot cycle; API quota exhaustion against the live account; testing on macOS 14 rather than the current macOS 26.5.1 host. These remain manual/real-world acceptance work, not checked-off successes.

## Plugin/skill use

Applied the local Apple design skill and retrieved the requested remote Apple design skill; used SwiftUI Expert, Build macOS Apps SwiftPM/packaging skills, Graphify navigation/update, current Context7/official Apple and Groq documentation, and Computer Use for actual UI inspection. FreakUI's generation tool was invoked and returned generation access unavailable for this account. No FreakUI-generated foundation is claimed. Native implementation continued under the user's instruction to complete other feasible work when a tool is unavailable.

## Required user setup

1. Open Flow → Get Started and grant Microphone, Accessibility and Input Monitoring through macOS. Recheck, then quit/reopen if needed.
2. Open Connection, enter your own Groq key, save it to Keychain and test model access.
3. Put the cursor in TextEdit and test Fn + Space with actual speech. If macOS intercepts Fn, explicitly choose a fallback in Shortcuts and test it.
4. Confirm transcription, cleanup, cancellation and final insertion in each app you use. Start at Login is implemented and registration-tested; enable it if wanted and verify on your next login.

No unresolved compiler/test failures remain. The unresolved release acceptance items are the live/OS-level tests listed above and public distribution trust (Developer ID/notarization). See KNOWN_LIMITATIONS.md for compatibility constraints.
