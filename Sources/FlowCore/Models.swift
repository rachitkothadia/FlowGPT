import Foundation

public enum FlowError: Error, Equatable, LocalizedError, Sendable {
    case missingKey, microphone, recording, tooShort, silent, audioTooLarge, emptyText, malformedResponse
    case authentication, rateLimited, service(Int), network, timeout, targetChanged, secureField, accessibility, insertion, clipboard, storage, shortcut, cancelled
    public var errorDescription: String? {
        switch self {
        case .missingKey: "Add your Groq API key in Settings → Connection."
        case .microphone: "Allow Microphone access in System Settings, then try again."
        case .recording: "The microphone could not record. Check your input device and try again."
        case .tooShort: "The recording was too short. Speak for at least half a second."
        case .silent: "No audible speech was detected. Check your microphone and try again."
        case .audioTooLarge: "This recording is too large to upload. Try a shorter dictation."
        case .emptyText: "Groq returned no usable text. Try again or copy the raw transcript."
        case .malformedResponse: "Groq returned an unexpected response. Your last available text is kept for recovery."
        case .authentication: "Groq rejected the API key. Replace it in Settings → Connection."
        case .rateLimited: "Groq is limiting requests. Wait briefly before trying again."
        case .service(let code): "Groq could not complete the request (HTTP \(code)). Try again later."
        case .network: "Could not reach Groq. Check your internet connection."
        case .timeout: "Groq did not respond in time. Try again."
        case .targetChanged: "The destination changed. Return to the original field and retry insertion, or copy your text."
        case .secureField: "Flow does not insert into password or secure fields. Copy your text if needed."
        case .accessibility: "Allow Accessibility access to insert text into other apps."
        case .insertion: "Text could not be inserted. Your result is available to copy."
        case .clipboard: "The clipboard could not be safely preserved. Copy your result manually."
        case .storage: "Local data could not be read or saved. Check available disk space and permissions."
        case .shortcut: "The shortcut could not be enabled. Allow Accessibility and Input Monitoring, then recheck."
        case .cancelled: "Dictation cancelled."
        }
    }
}
public enum DictationMode: String, Codable, CaseIterable, Sendable {
    case clean = "Clean Dictation", verbatim = "Verbatim", professional = "Professional", developer = "Developer", custom = "Custom"
    public func prompt(custom: String) -> String {
        DictationFormatting.instructions(mode: self, custom: custom)
    }
}
public struct Shortcut: Codable, Hashable, Sendable {
    public var keyCode: UInt16
    public var modifiers: UInt64
    public var label: String
    public init(keyCode: UInt16, modifiers: UInt64, label: String) { self.keyCode = keyCode; self.modifiers = modifiers; self.label = label }
    public static let fnSpace = Shortcut(keyCode: 49, modifiers: 1 << 23, label: "Fn + Space")
    public static let fallback = Shortcut(keyCode: 49, modifiers: (1 << 18) | (1 << 19), label: "Control + Option + Space")
    public static let commandShiftD = Shortcut(keyCode: 2, modifiers: (1 << 20) | (1 << 17), label: "Command + Shift + D")
    public static let modifierMask: UInt64 = (1 << 17) | (1 << 18) | (1 << 19) | (1 << 20) | (1 << 23)
    public var isValid: Bool { modifiers & Self.modifierMask != 0 && keyCode < 128 && ![53,54,55,56,58,59,60,61,62,63].contains(keyCode) }
    public func matches(code: UInt16, flags: UInt64) -> Bool { keyCode == code && flags & Self.modifierMask == modifiers }
}
public struct Preferences: Codable, Equatable, Sendable {
    public var mode: DictationMode = .clean
    public var cleanup = true
    public var customInstructions = ""
    public var language = ""
    public var shortcut = Shortcut.fnSpace
    public var shortcutEnabled = true
    public var pushToTalk = false
    public var showPanel = true
    public var autoDismiss = true
    public var historyEnabled = false
    public var preserveClipboard = true
    public var backgroundLaunch = true
    public var appearance = "System"
    public var continuous: Bool?
    public var accuracy: String?
    public var audioSource: String?
    public var isContinuous: Bool { continuous == true }
    public init() {}
    public mutating func sanitize() {
        if !shortcut.isValid { shortcut = .fnSpace }
        language = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !language.isEmpty && !LanguageCatalog.supportedCodes.contains(language) { language = "" }
        customInstructions = String(customInstructions.prefix(2000))
        if !["System", "Light", "Dark"].contains(appearance) { appearance = "System" }
        if let accuracy, !["Fast", "Accurate"].contains(accuracy) { self.accuracy = nil }
    }
}
public enum SessionState: String, Sendable {
    case idle, tip, starting, recording, transcribing, generating, inserting, success, attempted, error, cancelled
    public var busy: Bool { [.starting, .recording, .transcribing, .generating, .inserting].contains(self) }
}
public enum InsertionOutcome: Sendable { case confirmed, attempted }
public struct DictationResult: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var raw: String
    public var final: String
    public var mode: DictationMode
    public init(raw: String, final: String, mode: DictationMode) { self.raw = raw; self.final = final; self.mode = mode }
}
public enum TextValidation {
    public static func validate(_ text: String) throws -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw FlowError.emptyText }
        guard clean.utf8.count <= 100_000, !clean.contains("\0"), !clean.contains("<think>"), !clean.contains("</think>") else { throw FlowError.malformedResponse }
        return clean
    }
}
public enum ClipboardGuard {
    public static func mayRestore(writtenCount: Int, currentCount: Int) -> Bool { writtenCount == currentCount }
}
public enum LoginPolicy {
    public static func needsChange(enabled: Bool, currentlyEnabled: Bool) -> Bool { enabled != currentlyEnabled }
}

public struct ShortcutInterpreter: Sendable {
    public enum Action: Equatable, Sendable { case none, press, release }
    public private(set) var held = false
    public init() {}
    public mutating func keyDown(matches: Bool, isRepeat: Bool) -> Action {
        guard matches, !held, !isRepeat else { return .none }; held = true; return .press
    }
    public mutating func release() -> Action {
        guard held else { return .none }; held = false; return .release
    }
    public mutating func reset() { held = false }
}
