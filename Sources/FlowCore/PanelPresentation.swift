/// Presentation only: finishing recording stays visible during transcription,
/// formatting and insertion. Completed delivery immediately hides the panel.
public enum PanelPresentation: Equatable, Sendable {
    case hidden, recording, processing, error
    public init(state: SessionState) {
        switch state {
        case .recording: self = .recording
        case .starting, .transcribing, .generating, .inserting: self = .processing
        case .error: self = .error
        case .idle, .success, .attempted, .cancelled, .tip: self = .hidden
        }
    }
}
