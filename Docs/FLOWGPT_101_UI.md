# FlowGpt 1.0.1 interface validation

The former single-column prototype mixed connection controls, permission buttons,
help text and full transcripts. The permission controls competed for horizontal
space. The replacement uses native NavigationSplitView navigation for Overview,
History and Settings, separate permission rows, local history search, readable
text wrapping and a compact Liquid Glass microphone/loader strip.

## Scope

Production transcription, insertion, permission APIs, account storage and history
serialization were preserved. The model gained an isolated visual-fixture mode,
selected only by the dedicated design-preview launcher. It uses in-memory sample
history, never loads ChatGPT or stored history, never starts a shortcut monitor,
and never requests microphone or macOS privacy access. Its sample status labels
are visibly marked Design preview. They do not establish real permission grants.

FreakUI's add-component skill/component map, SwiftUI Expert, Build macOS Apps
Liquid Glass/build skills and the project Apple-design SKILL.md guided the work.
The available FreakUI generator is restricted to new app foundations and was not
called on this existing app. No FreakUI SDK dependency was added.

## Verification

- Arm64 release compiled with warnings treated as errors; 105 existing software
  tests passed. These are not 105 UI or speech-accuracy tests.
- Native app visual inspection checked all three pages, compact settings at a
  760×580 content size, light and dark appearances, mixed-script history wrapping,
  a matching search, the no-results state and clearing the search.
- The actual recording-strip SwiftUI view rendered its microphone and waveform
  in the visual fixture. Clicking its microphone replaced it with the processing
  spinner. Hiding the strip removed it. The fixture kept the microphone off.
- macOS 26 uses native glassEffect; the source gates it with a material fallback
  for macOS 14–25. The earlier-system fallback was compiled, not run on an older
  Mac. Reduced Motion disables the waveform effect; Reduced Transparency uses a
  solid surface. Those settings were not changed on the user's system.
- The Run script and Codex Run action now target FlowGpt instead of retired Flow
  paths. Signing, mount checks and checksum results are in release/flowgpt.

Screenshots under QA/FlowGpt-UI are visual fixtures using sample transcripts.
The screenshot called recording-strip was captured inside the preview window so
its appearance could be inspected; the production panel is nonactivating.

## Distribution

FlowGpt-1.0.1-arm64.dmg is placed directly in the project root. No TCC resets,
permission toggles or account sign-ins were performed for this interface change.
The existing installed app is not replaced automatically during UI previews.
Install the final UI build before completing its permission setup. As with earlier
locally signed builds, macOS can require renewed approval after installation.
Global shortcut and automatic insertion verification still depend on those grants.
