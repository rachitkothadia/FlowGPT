# Permissions

Use Get Started to request Microphone, Accessibility and Input Monitoring through macOS. Flow never edits TCC or bypasses consent.

FlowGPT indicators use public permission APIs in the running app. A short-lived helper can detect a cached keyboard denial and suggest reopening, but its denial cannot overwrite an effective app grant and its microphone result cannot authorize this process. Helper probes time out after two seconds. An already authorized microphone is not requested again. No permission choices are stored as fake grants in app preferences. No TCC resets are performed.

Install and run one copy in `/Applications/FlowGpt.app`. The ad hoc preview signature changes when the binary is rebuilt, so an update may need refreshed grants. Reopening an unchanged build should preserve system grants. A stable Developer ID certificate is required to reliably preserve app identity across upgrades.

Input Monitoring can require explicit registration through System Settings → Privacy & Security → Input Monitoring → + → /Applications/FlowGpt.app. The Allow action first calls CGRequestListenEventAccess and attempts a temporary read-only tap independently of Accessibility. If macOS does not create a row, use the + path. macOS itself displayed “Flow will not be able to monitor input ... until it is quit” during validation. The indicator can update immediately while applying a first keyboard grant may still require reopening Flow. The app reopens automatically once when Accessibility is freshly granted but cached as denied, provided no dictation or recoverable result is active. Repeated automatic restarts are prevented. The in-app Restart Flow button waits for graceful termination before relaunching; it never claims to bypass this OS requirement.

Microphone is used only after starting dictation. Accessibility permits focused-field insertion and the consuming shortcut tap. Input Monitoring permits keyboard capture. Missing access disables the shortcut; no checkbox in Flow grants OS consent. A shortcut may conflict with Fn/Globe system settings; choose an alternative under Shortcuts.

The public Input Monitoring preflight reports effective keyboard access. macOS can authorize that access through Accessibility as well, even when a separate Input Monitoring switch is off. The indicator describes actual API authorization, not a private TCC database row.
