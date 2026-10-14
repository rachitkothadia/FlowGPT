import Foundation
import Observation

public enum BrowserBridgeError: LocalizedError, Equatable {
    case unavailable(String)
    public var errorDescription: String? { switch self { case .unavailable(let message): message } }
}

@MainActor public protocol BrowserDictationDriver: AnyObject {
    func start() async throws
    func finish() async throws -> String
    func discard(_ expected: String) async throws
    func cancel() async
}

/// A browser transcript is delivered verbatim. No API key or formatter participates.
@MainActor @Observable public final class BrowserDictationSession {
    public private(set) var state: SessionState = .idle
    public private(set) var message = "Connect ChatGPT to begin"
    public private(set) var text = ""
    public private(set) var localPreview = false
    public var onState: ((SessionState) -> Void)?
    public var saveResult: ((DictationResult) async throws -> Void)?
    private let browser: any BrowserDictationDriver
    private let insertion: any TextInsertion
    private var generation = UUID()
    private var work: Task<Void, Never>?
    private var stopAfterStart = false
    public init(browser: any BrowserDictationDriver, insertion: any TextInsertion) {
        self.browser = browser; self.insertion = insertion
    }
    private func set(_ state: SessionState, _ message: String) {
        self.state = state; self.message = message; onState?(state)
    }
    public func toggle(localPreview: Bool = false) {
        if state == .recording { finish(); return }
        if state == .starting { finish(); return }
        guard !state.busy else { return }
        generation = UUID(); let token = generation
        text = ""; self.localPreview = localPreview
        stopAfterStart = false
        if localPreview { insertion.reset() } else { insertion.captureTarget() }
        set(.starting, "Starting ChatGPT dictation…")
        work = Task {
            do {
                try await browser.start()
                try Task.checkCancellation(); guard generation == token else { return }
                set(.recording, "Recording your voice")
                if stopAfterStart { finish() }
            } catch {
                guard generation == token else { return }
                await browser.cancel()
                guard generation == token else { return }
                set(.error, error.localizedDescription)
            }
        }
    }
    public func finish() {
        if state == .starting { stopAfterStart = true; return }
        guard state == .recording else { return }
        let token = generation
        set(.transcribing, "Waiting for ChatGPT transcription…")
        work = Task {
            do {
                let transcript = try await browser.finish()
                try Task.checkCancellation(); guard generation == token else { return }
                let raw = try TextValidation.validate(transcript)
                text = ConservativeFormatting.format(raw)
                // Persist before clearing the owned draft or attempting insertion.
                // If persistence fails the browser draft is kept for recovery.
                try await saveResult?(DictationResult(raw: raw, final: text, mode: .verbatim))
                try Task.checkCancellation(); guard generation == token else { return }
                var draftNotice = ""
                do { try await browser.discard(raw) }
                catch { draftNotice = " · ChatGPT draft kept; clear it before recording again" }
                try Task.checkCancellation(); guard generation == token else { return }
                if localPreview { set(.success, "Transcript saved in FlowGpt" + draftNotice); return }
                set(.inserting, "Inserting…")
                let outcome = try await insertion.insert(text, preserveClipboard: true)
                try Task.checkCancellation(); guard generation == token else { return }
                set(outcome == .confirmed ? .success : .attempted,
                    (outcome == .confirmed ? "Inserted" : "Saved; insertion could not be verified") + draftNotice)
            } catch {
                guard generation == token else { return }
                await browser.cancel()
                guard generation == token else { return }
                set(.error, error.localizedDescription)
            }
        }
    }
    public func cancel() {
        guard state.busy else { return }
        let pending = work
        generation = UUID(); pending?.cancel()
        stopAfterStart = false
        set(.starting, "Cancelling browser dictation…")
        work = Task { await pending?.value; await browser.cancel(); insertion.reset(); set(.cancelled, "Cancelled") }
    }
    public func shutdown() async {
        if state.busy { cancel() }
        await work?.value
        await browser.cancel()
    }
}
