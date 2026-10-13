# Flow 3.0.2 recording popup

## Behavior

The visible control is one compact 150 × 36 point rounded rectangle, with transparent margins for its shadow. macOS 26 uses Apple's native interactive Liquid Glass; earlier macOS versions use adaptive ultra-thin material. Reduce Transparency uses a solid accessible surface. The panel remains nonactivating and cannot become key or main, so it does not take the editor's typing focus.

While recording, the mic and waveform share one row. Pressing Fn + Space again uses the existing stop action: the mic immediately becomes a native indeterminate spinner during transcription, formatting and insertion. The waveform becomes a subtle idle line instead of displaying stale microphone levels. There is no visible status text or multiline card.

Successful or unverified completed delivery immediately hides the panel. The old 1.2 second success delay is removed. Idle/cancelled states also hide it. Errors remain recoverable through a compact warning icon and the result/menu actions. Results remain available in History even after the panel closes. Flow Settings recordings retain their existing local-preview behavior.

Automatic insertion retains 3.0.1's native paste and clipboard restoration. Shortcut, microphone, Accessibility and Input Monitoring implementations were not modified. This update does not add silence detection or change transcription accuracy: the second Fn + Space press finishes recording.

## Verification on 11 October 2026

- 127 automated tests in 14 suites passed. Three presentation tests cover recording → processing → delivery → hidden, immediate completed/cancelled dismissal and recoverable error presentation.
- Production release compilation succeeded with warnings treated as errors.
- A separate project-local signed .app preview was launched through computer-control tooling. It used the actual SessionController, PanelController and RecordingPanelView with synthetic audio, text and insertion adapters. No microphone, API call or privacy-grant change was made by this preview.
- Native UI observations showed recording with popup visible; generating/inserting with popup visible and an accessibility busy indicator replacing the mic; then success with the completed demo text and popup hidden.
- Native screenshots inspected the same production view against a gradient: one glass surface, readable mic/waveform, same-size spinner/idle line, and no remaining view after completion. The inset sample exists only in the isolated preview, never the shipping settings page.
- The synthetic preview verifies panel behavior and rendering, not real microphone capture or an end-to-end Fn-key/API session. Prior 3.0.1 live browser insertion results remain documented separately.

The installer is Flow-3.0.2-arm64.dmg directly in the project root. It is a local ad hoc signed arm64 build, without Developer ID or notarization. Existing installed apps and privacy entries are not reset or replaced by packaging.

## Reference

[Apple: applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views) describes system glass and explicit shapes. The implementation uses availability checks rather than a custom imitation on macOS 26.
