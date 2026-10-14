import Foundation

/// Whitespace-only presentation. No vocabulary, language, or semantic inference.
public enum ConservativeFormatting {
    public static func format(_ raw: String) -> String {
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n")
        // Preserve protected literal blocks and inline code exactly.
        guard !["`", "\"", "'", "“", "”", "‘", "’"].contains(where: text.contains), !text.contains("http://"), !text.contains("https://"),
              !text.contains("\\"), !text.contains("/") else { return raw }
        let pattern = #"(?:^|[ \t\n])([0-9]+)\.[ \t]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return raw }
        let source = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: source.length))
        // Only an explicit sequence beginning at 1 is a list. Do not infer a list
        // from shopping words, "first", language, pauses, or ordinary conversation.
        guard matches.count >= 2, let first = matches.first,
              first.range.location == 0 || source.substring(to: first.range.location).trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(":"),
              matches.enumerated().allSatisfy({ index, match in
            source.substring(with: match.range(at: 1)) == String(index + 1)
        }) else { return raw }
        var result = text
        for match in matches.reversed() where match.range.location > 0 {
            let prefix = source.substring(with: NSRange(location: match.range.location, length: 1))
            guard prefix == " " || prefix == "\t", let range = Range(NSRange(location: match.range.location, length: 1), in: result) else { continue }
            result.replaceSubrange(range, with: "\n")
        }
        return result
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
