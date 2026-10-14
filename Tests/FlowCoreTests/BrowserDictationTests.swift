import Foundation
import Testing
@testable import FlowCore

@MainActor private final class FakeBrowser: BrowserDictationDriver {
    var starts = 0, finishes = 0, discards = 0, cancels = 0
    var transcript = "अरे hello, आज meeting आहे।"
    var failure: BrowserBridgeError?
    var delay: Duration = .zero
    var startDelay: Duration = .zero
    var discardFails = false
    var owns = false
    func start() async throws {
        starts += 1
        if startDelay != .zero { try await Task.sleep(for: startDelay) }
        if owns { throw BrowserBridgeError.unavailable("Already recording") }
        if let failure { throw failure }
        owns = true
    }
    func finish() async throws -> String {
        finishes += 1
        if delay != .zero { try await Task.sleep(for: delay) }
        if let failure { throw failure }
        return transcript
    }
    func discard(_ expected: String) async throws {
        defer { owns = false }
        discards += 1
        if discardFails { throw BrowserBridgeError.unavailable("Draft changed") }
        #expect(expected == transcript)
    }
    func cancel() async { cancels += 1; owns = false }
}

struct BrowserDictationTests {
    @MainActor private func wait(_ expected: SessionState, _ session: BrowserDictationSession) async {
        for _ in 0..<200 {
            if session.state == expected { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Expected \(expected), got \(session.state): \(session.message)")
    }
    @Test @MainActor func verbatimPersistsBeforeDiscardAndInsertion() async {
        let browser = FakeBrowser(), insertion = MockInsertion()
        let session = BrowserDictationSession(browser: browser, insertion: insertion)
        var saved: [DictationResult] = []
        session.saveResult = { result in
            #expect(browser.discards == 0 && insertion.inserts == 0)
            saved.append(result)
        }
        session.toggle(); await wait(.recording, session)
        session.finish(); await wait(.success, session)
        #expect(saved.count == 1 && saved[0].raw == browser.transcript && saved[0].final == browser.transcript)
        #expect(saved[0].mode == .verbatim)
        #expect(insertion.inserted == [browser.transcript] && browser.discards == 1)
    }
    @Test @MainActor func saveFailureLeavesDraftAndDoesNotPaste() async {
        let browser = FakeBrowser(), insertion = MockInsertion()
        let session = BrowserDictationSession(browser: browser, insertion: insertion)
        session.saveResult = { _ in throw FlowError.storage }
        session.toggle(); await wait(.recording, session); session.finish(); await wait(.error, session)
        #expect(session.text == browser.transcript && browser.discards == 0 && insertion.inserts == 0)
    }
    @Test @MainActor func changedDraftIsKeptButSavedTextDeliveredOnce() async {
        let browser = FakeBrowser(), insertion = MockInsertion(); browser.discardFails = true
        let session = BrowserDictationSession(browser: browser, insertion: insertion)
        session.toggle(); await wait(.recording, session); session.finish(); await wait(.success, session)
        #expect(session.message.contains("draft kept") && insertion.inserts == 1)
    }
    @Test @MainActor func localPreviewNeverInsertsIntoSettings() async {
        let browser = FakeBrowser(), insertion = MockInsertion()
        let session = BrowserDictationSession(browser: browser, insertion: insertion)
        session.toggle(localPreview: true); await wait(.recording, session); session.finish(); await wait(.success, session)
        #expect(insertion.captures == 0 && insertion.inserts == 0 && session.text == browser.transcript)
    }
    @Test @MainActor func rapidToggleDoesNotStartTwiceOrPasteTwice() async {
        let browser = FakeBrowser(), insertion = MockInsertion()
        let session = BrowserDictationSession(browser: browser, insertion: insertion)
        session.toggle()
        await wait(.recording, session)
        for _ in 0..<10 { session.toggle() }
        await wait(.success, session)
        #expect(browser.starts == 1 && browser.finishes == 1 && insertion.inserts == 1)
    }
    @Test @MainActor func stopDuringStartupIsRememberedWithoutLosingTarget() async {
        let browser = FakeBrowser(), insertion = MockInsertion(); browser.startDelay = .milliseconds(80)
        let session = BrowserDictationSession(browser: browser, insertion: insertion)
        session.toggle(); session.toggle()
        await wait(.success, session)
        #expect(browser.starts == 1 && browser.finishes == 1 && insertion.captures == 1 && insertion.inserts == 1)
    }
    @Test @MainActor func cancellationDuringStartupNeverInserts() async {
        let browser = FakeBrowser(), insertion = MockInsertion(); browser.startDelay = .seconds(1)
        let session = BrowserDictationSession(browser: browser, insertion: insertion)
        session.toggle(); session.cancel(); await wait(.cancelled, session)
        #expect(browser.finishes == 0 && insertion.inserts == 0 && !browser.owns)
    }
    @Test @MainActor func cancellationDuringTranscriptionNeverSavesOrPastes() async {
        let browser = FakeBrowser(), insertion = MockInsertion(); browser.delay = .seconds(1)
        let session = BrowserDictationSession(browser: browser, insertion: insertion)
        var saved = 0; session.saveResult = { _ in saved += 1 }
        session.toggle(); await wait(.recording, session); session.finish(); session.cancel()
        await wait(.cancelled, session)
        #expect(saved == 0 && insertion.inserts == 0 && browser.cancels > 0)
    }
    @Test @MainActor func noSpeechDoesNotCreateHistoryOrInsertion() async {
        let browser = FakeBrowser(), insertion = MockInsertion(); browser.transcript = "  "
        let session = BrowserDictationSession(browser: browser, insertion: insertion)
        var saved = 0; session.saveResult = { _ in saved += 1 }
        session.toggle(); await wait(.recording, session); session.finish(); await wait(.error, session)
        #expect(saved == 0 && insertion.inserts == 0 && browser.discards == 0)
    }
    @Test @MainActor func emptySpeechReleasesBrowserForNextRecording() async {
        let browser = FakeBrowser(), insertion = MockInsertion(); browser.transcript = ""
        let session = BrowserDictationSession(browser: browser, insertion: insertion)
        session.toggle(); await wait(.recording, session); session.finish(); await wait(.error, session)
        #expect(!browser.owns)
        browser.transcript = "Next recording works."
        session.toggle(); await wait(.recording, session); session.finish(); await wait(.success, session)
        #expect(insertion.inserted == ["Next recording works."])
    }
    @Test @MainActor func unavailableBrowserIsAnErrorWithoutGroqFallback() async {
        let browser = FakeBrowser(), insertion = MockInsertion()
        browser.failure = .unavailable("Please sign in")
        let session = BrowserDictationSession(browser: browser, insertion: insertion)
        session.toggle(); await wait(.error, session)
        #expect(session.message == "Please sign in" && insertion.inserts == 0 && browser.finishes == 0)
    }
    @Test @MainActor func insertionFailureKeepsRecoveredTranscript() async {
        let browser = FakeBrowser(), insertion = MockInsertion(); insertion.error = .insertion
        let session = BrowserDictationSession(browser: browser, insertion: insertion)
        var saved: String?; session.saveResult = { saved = $0.final }
        session.toggle(); await wait(.recording, session); session.finish(); await wait(.error, session)
        #expect(saved == browser.transcript && session.text == browser.transcript && browser.discards == 1)
    }
    @Test @MainActor func presentationKeepsRawAndDiscardsOnlyOwnedUnformattedDraft() async {
        let browser = FakeBrowser(), insertion = MockInsertion()
        browser.transcript = "Tasks: 1. shopping 2. Dad ला call कर"
        let session = BrowserDictationSession(browser: browser, insertion: insertion)
        var saved: DictationResult?
        session.saveResult = { saved = $0 }
        session.toggle(); await wait(.recording, session); session.finish(); await wait(.success, session)
        #expect(saved?.raw == browser.transcript)
        #expect(saved?.final == "Tasks:\n1. shopping\n2. Dad ला call कर")
        #expect(insertion.inserted == [saved!.final] && browser.discards == 1)
    }
}
