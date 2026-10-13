# FlowGpt 1.0.3

Native macOS dictation using ChatGPT's consumer dictation page in an embedded
WebKit session. This is browser automation, not official OAuth or a speech API.
No separate Chrome, Selenium, MCP server or ChatGPT desktop app is required.

Overview contains the shortcut and a local dictation preview. History contains
full selectable transcripts and local search. Settings contains your ChatGPT
connection and three separate permission rows. The floating recording strip uses
native Liquid Glass on macOS 26, with a material fallback on earlier versions.

Choose Continue with ChatGPT once and sign in yourself. Close the connection
window afterward. Website data is stored persistently by WebKit. On later
launches FlowGpt restores the page without displaying that window. If OpenAI
expires or revokes your session, Manage connection lets you sign in again.

Focus an editable destination and press Fn + Space to start. Press again to stop.
Temporary Chat is prepared as the connection loads, before recording. Opening
audio is captured directly by Swift's AVFoundation microphone capture into a bounded
in-memory buffer while ChatGPT initializes its recorder. Local capture does not
wait for the browser, JavaScript or network. The recording indicator starts once
native capture starts; its waveform uses real microphone levels. Stop freezes capture immediately and
drains that audio before asking ChatGPT to transcribe. Initialization/network
latency still exists, and the buffered tail can extend processing time. A second
shortcut press during startup is remembered, not discarded. Audio is never
connected to the speakers or stored in a local recording file. The built-in Mac
microphone is selected for this capture session without changing the system input
device, avoiding Bluetooth headset microphone switching when available. Other
machines use the system microphone. No volume keys or
system volume setters are called.
The microphone popup becomes a loader during transcription and disappears after
insertion. The transcript is saved before the matching unsent draft is removed.
Native paste restores your clipboard. No ChatGPT message is sent.
The 104×32-point visible strip sits near the bottom of the usable screen area,
above the Dock. Closing Settings leaves the menu-bar app running. Completion,
failed insertion and errors never reopen that window; their status is available
in the menu bar and History. Settings has no minimize-to-Dock action.
An idle connection watchdog rechecks readiness and reconnects after transport or
renderer failures with bounded retry delays. Cancelled navigations are ignored.
Wake from sleep triggers a check. A visible unsent draft, active dictation or a
login page prevents automatic reload. Expired/revoked accounts still require a
manual sign-in; saving website data cannot guarantee a permanent login.

Allow Microphone, Accessibility and Input Monitoring when macOS requests them.
Grants belong to macOS and are reused by the same installed build. Rebuilt ad hoc
signed apps may need renewed approval. This Mac currently has no valid signing
certificate; the package is locally signed and is not notarized. FlowGpt never
resets privacy grants or alters the TCC database. The mic records only during
explicitly started dictation, not continuously.

The historical bundle ID in.vardaan.flow and Application Support/Flow data folder
are retained deliberately to preserve WebKit login and local transcript history.
Your old history, API key and unused NLP data are not deleted. The public app name,
executable and installer are FlowGpt. No Groq requests or NLP rewriting run here.

Temporary Chat is verified before recording. It does not guarantee zero OpenAI
retention. This version supports short dictation, not multi-hour lectures.
Network failures, expired login, unavailable microphone, changed draft or UI
changes report an error rather than claiming text was inserted.

Build: Scripts/build-flowgpt.sh. Installer: FlowGpt-1.0.3-arm64.dmg, directly in the
project folder. Native tests and packaging results are under release/flowgpt.
Live recording, shortcut and insertion results must be verified separately from
software tests; the software test count is not an audio accuracy score.
