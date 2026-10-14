import Foundation
import FlowFormatting

/// Native presentation shared with Windows. The provider's original remains in History.
public enum ConservativeFormatting {
    public static func format(_ raw: String) -> String {
        guard let result = raw.withCString({ flow_format_transcript($0) }) else { return raw }
        defer { flow_free_transcript(result) }
        return String(cString: result)
    }
}

/// A completion signal plus stable text is required, never elapsed time alone.
public struct TranscriptCompletion: Sendable {
    public static let stabilityInterval: TimeInterval = 0.2
    private var candidate = ""
    private var changedAt: TimeInterval = 0
    public init() {}
    public mutating func observe(text: String, ready: Bool, transcribing: Bool, recording: Bool, at time: TimeInterval) -> String? {
        guard ready, !transcribing, !recording, !text.isEmpty else { candidate = ""; return nil }
        if text != candidate { candidate = text; changedAt = time; return nil }
        return time - changedAt >= Self.stabilityInterval ? candidate : nil
    }
}
