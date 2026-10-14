/// A helper's privacy context may differ from the foreground app's context.
/// Never downgrade a live effective grant based on a helper denial, and never
/// present a helper microphone grant as authorization to record in this process.
public struct PermissionReading: Equatable, Sendable {
    public let microphone: Bool
    public let accessibility: Bool
    public let inputMonitoring: Bool
    public let needsRestart: Bool
    public init(microphone: Bool, accessibility: Bool, inputMonitoring: Bool,
                helperAccessibility: Bool = false, helperInput: Bool = false) {
        self.microphone = microphone
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
        needsRestart = (!accessibility && helperAccessibility) || (!inputMonitoring && helperInput)
    }
}

public enum BrowserMicrophoneConsent {
    /// An idle page must not create another browser consent prompt on relaunch.
    /// The native recording action already obtains OS consent before ownership.
    public static func mayDelegate(recordingOwned: Bool, osAuthorized: Bool) -> Bool {
        recordingOwned && osAuthorized
    }
}
