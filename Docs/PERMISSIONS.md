# Permissions

Use Get Started to request Microphone, Accessibility and Input Monitoring through macOS. Flow never edits TCC or bypasses consent.

Indicators refresh automatically every three seconds and on app activation. A short-lived instance of the same signed app reads all three public permission APIs, avoiding stale Core Graphics permission values cached in a long-running process. All three indicators use the fresh-process snapshot. The main app’s Accessibility status is compared to detect a stale denial. No keyboard events, recordings or user data are collected by this check. Grant/revoke changes redraw observed state and reconfigure the shortcut. Revoking keyboard access cancels an active session.

Input Monitoring can require explicit registration through System Settings → Privacy & Security → Input Monitoring → + → /Applications/Flow.app. The Allow action first calls CGRequestListenEventAccess and attempts a temporary read-only tap independently of Accessibility. If macOS does not create a row, use the + path. macOS itself displayed “Flow will not be able to monitor input ... until it is quit” during validation. The indicator can update immediately while applying a first keyboard grant may still require reopening Flow. The app reopens automatically once when Accessibility is freshly granted but cached as denied, provided no dictation or recoverable result is active. Repeated automatic restarts are prevented. The in-app Restart Flow button waits for graceful termination before relaunching; it never claims to bypass this OS requirement.

Microphone is used only after starting dictation. Accessibility permits focused-field insertion and the consuming shortcut tap. Input Monitoring permits keyboard capture. Missing access disables the shortcut; no checkbox in Flow grants OS consent. A shortcut may conflict with Fn/Globe system settings; choose an alternative under Shortcuts.

The public Input Monitoring preflight reports effective keyboard access. macOS can authorize that access through Accessibility as well, even when a separate Input Monitoring switch is off. The indicator describes actual API authorization, not a private TCC database row.
