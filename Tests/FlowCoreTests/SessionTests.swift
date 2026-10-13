import Testing
import Foundation
@testable import FlowCore

@MainActor final class MockAudio: AudioCapture {
    var starts = 0; var stops = 0; var cancels = 0
    var level = 0.5; var elapsed: TimeInterval = 1
    var startError: FlowError?; var stopError: FlowError?
    var startDelay: Duration = .zero
    var url: URL
    init() { url = FileManager.default.temporaryDirectory.appendingPathComponent("Flow-test-" + UUID().uuidString + ".m4a") }
    func start() async throws {
        starts += 1
        if startDelay != .zero { try await Task.sleep(for: startDelay) }
        if let startError { throw startError }
        try Data([1,2,3]).write(to: url)
    }
    func stop() throws -> URL { stops += 1; if let stopError { throw stopError }; return url }
    func cancel() { cancels += 1; if FileManager.default.fileExists(atPath: url.path) { try? FileManager.default.removeItem(at: url) } }
}
actor MockPipeline: TextPipeline {
    var transcriptions = 0; var cleanups = 0
    let delay: Duration; let error: FlowError?
    let cleanDelay: Duration; let cleanError: FlowError?
    let ignoreCancellation: Bool
    init(delay: Duration = .zero, error: FlowError? = nil, ignoreCancellation: Bool = false, cleanDelay: Duration = .zero, cleanError: FlowError? = nil) { self.delay = delay; self.error = error; self.ignoreCancellation = ignoreCancellation; self.cleanDelay = cleanDelay; self.cleanError = cleanError }
    func transcribe(audio: URL, key: String, preferences: Preferences) async throws -> String {
        transcriptions += 1
        if delay != .zero {
            if ignoreCancellation { await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { c.resume() } } }
            else { try await Task.sleep(for: delay) }
        }
        if let error { throw error }
        return "hello world"
    }
    func clean(text: String, key: String, preferences: Preferences) async throws -> String { cleanups += 1; if cleanDelay != .zero { try await Task.sleep(for: cleanDelay) }; if let cleanError { throw cleanError }; return preferences.cleanup ? "Hello, world." : text }
}
@MainActor final class MockInsertion: TextInsertion {
    var captures = 0; var inserts = 0; var resets = 0
    var error: FlowError?; var result: InsertionOutcome = .confirmed
    var inserted: [String] = []
    func captureTarget() { captures += 1 }
    func insert(_ text: String, preserveClipboard: Bool) async throws -> InsertionOutcome { inserts += 1; if let error { throw error }; inserted.append(text); return result }
    func reset() { resets += 1 }
}
struct SessionTests {
    @MainActor private func waitFor(_ state: SessionState, _ session: SessionController) async {
        for _ in 0..<100 {
            if session.state == state { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("State was \(session.state), expected \(state)")
    }
    @Test @MainActor func testFullPipelineAndTemporaryCleanup() async {
        let audio = MockAudio(); let insertion = MockInsertion(); let pipeline = MockPipeline()
        let session = SessionController(audio: audio, pipeline: pipeline, insertion: insertion)
        var states: [SessionState] = []; session.onState = { states.append($0) }
        session.begin(key: "test", preferences: Preferences()); #expect(session.state ==  .starting)
        await waitFor(.recording, session); session.stop(); await waitFor(.success, session)
        #expect(insertion.inserted ==  ["Hello, world."])
        #expect(states ==  [.starting, .recording, .transcribing, .generating, .inserting, .success])
        #expect(!(FileManager.default.fileExists(atPath: audio.url.path))); #expect(!(session.canRetryInsertion))
        session.retryInsertion(); #expect(insertion.inserts ==  1)
    }
    @Test @MainActor func testRecordingInFlowStaysActiveAndNeverWritesSettings() async {
        let audio = MockAudio(); let insertion = MockInsertion()
        let session = SessionController(audio: audio, pipeline: MockPipeline(), insertion: insertion)
        session.begin(key: "test", preferences: Preferences(), insertIntoTarget: false)
        await waitFor(.recording, session)
        try? await Task.sleep(for: .milliseconds(1300))
        session.tick(); session.dismiss()
        #expect(session.state == .recording)
        #expect(audio.starts == 1 && audio.stops == 0)
        session.stop(); await waitFor(.success, session)
        #expect(session.rawText == "hello world")
        #expect(session.finalText == "Hello, world.")
        #expect(insertion.inserts == 0 && !session.canRetryInsertion)
        #expect(!FileManager.default.fileExists(atPath: audio.url.path))
        session.begin(key: "test", preferences: Preferences())
        await waitFor(.recording, session)
        session.stop(); await waitFor(.success, session)
        #expect(insertion.inserts == 1)
    }
    @Test @MainActor func testRapidToggleDoesNotDuplicateSession() async {
        let audio = MockAudio(); audio.startDelay = .milliseconds(30)
        let insertion = MockInsertion(); let pipeline = MockPipeline(delay: .milliseconds(30))
        let session = SessionController(audio: audio, pipeline: pipeline, insertion: insertion)
        for _ in 0..<10 { session.toggle(key: "test", preferences: Preferences()) }
        await waitFor(.recording, session); #expect(audio.starts ==  1)
        for _ in 0..<10 { session.toggle(key: "test", preferences: Preferences()) }
        await waitFor(.success, session)
        #expect(audio.stops ==  1); #expect(insertion.inserts ==  1)
        let count = await pipeline.transcriptions; #expect(count ==  1)
    }
    @Test @MainActor func testCancelWhileStarting() async {
        let audio = MockAudio(); audio.startDelay = .seconds(2); let insertion = MockInsertion()
        let session = SessionController(audio: audio, pipeline: MockPipeline(), insertion: insertion)
        session.begin(key: "test", preferences: Preferences()); session.cancel()
        try? await Task.sleep(for: .milliseconds(20))
        #expect(session.state ==  .cancelled); #expect(insertion.inserts ==  0); #expect(audio.cancels >  0)
    }
    @Test @MainActor func testCancelWhileRecording() async {
        let audio = MockAudio(); let insertion = MockInsertion(); let session = SessionController(audio: audio, pipeline: MockPipeline(), insertion: insertion)
        session.begin(key: "test", preferences: Preferences()); await waitFor(.recording, session); session.cancel()
        #expect(session.state ==  .cancelled); #expect(insertion.inserts ==  0); #expect(!(FileManager.default.fileExists(atPath: audio.url.path)))
    }
    @Test @MainActor func testCancelDuringTranscriptionPreventsStaleInsertion() async {
        let audio = MockAudio(); let insertion = MockInsertion()
        let session = SessionController(audio: audio, pipeline: MockPipeline(delay: .milliseconds(100), ignoreCancellation: true), insertion: insertion)
        session.begin(key: "test", preferences: Preferences()); await waitFor(.recording, session); session.stop()
        try? await Task.sleep(for: .milliseconds(10)); session.cancel(); try? await Task.sleep(for: .milliseconds(150))
        #expect(session.state ==  .cancelled); #expect(insertion.inserts ==  0); #expect(!(FileManager.default.fileExists(atPath: audio.url.path)))
    }
    @Test @MainActor func testMissingKeyDoesNotRecord() async {
        let audio = MockAudio(); let session = SessionController(audio: audio, pipeline: MockPipeline(), insertion: MockInsertion())
        session.begin(key: "", preferences: Preferences()); #expect(session.state ==  .error); #expect(audio.starts ==  0)
    }
    @Test @MainActor func testMicrophoneDeniedRecovers() async {
        let audio = MockAudio(); audio.startError = .microphone
        let session = SessionController(audio: audio, pipeline: MockPipeline(), insertion: MockInsertion())
        session.begin(key: "test", preferences: Preferences()); await waitFor(.error, session)
        #expect(session.message ==  FlowError.microphone.localizedDescription)
        audio.startError = nil; session.begin(key: "test", preferences: Preferences()); await waitFor(.recording, session); session.cancel()
    }
    @Test @MainActor func testEmptyRecordingDoesNotCallPipeline() async {
        let audio = MockAudio(); audio.stopError = .tooShort; let pipeline = MockPipeline()
        let session = SessionController(audio: audio, pipeline: pipeline, insertion: MockInsertion())
        session.begin(key: "test", preferences: Preferences()); await waitFor(.recording, session); session.stop()
        #expect(session.state ==  .error); let count = await pipeline.transcriptions; #expect(count ==  0)
    }
    @Test @MainActor func testNetworkFailureCleansAudio() async {
        let audio = MockAudio(); let session = SessionController(audio: audio, pipeline: MockPipeline(error: .network), insertion: MockInsertion())
        session.begin(key: "test", preferences: Preferences()); await waitFor(.recording, session); session.stop(); await waitFor(.error, session)
        #expect(!(FileManager.default.fileExists(atPath: audio.url.path)))
    }
    @Test @MainActor func testTargetChangePreservesFinalAndAllowsSafeRetry() async {
        let audio = MockAudio(); let insertion = MockInsertion(); insertion.error = .targetChanged
        let session = SessionController(audio: audio, pipeline: MockPipeline(), insertion: insertion)
        session.begin(key: "test", preferences: Preferences()); await waitFor(.recording, session); session.stop(); await waitFor(.error, session)
        #expect(session.finalText ==  "Hello, world."); #expect(session.canRetryInsertion)
        insertion.error = nil; session.retryInsertion(); await waitFor(.success, session); #expect(insertion.inserted.count ==  1)
    }
    @Test @MainActor func testUnverifiedPasteIsNotReportedAsConfirmed() async {
        let audio = MockAudio(); let insertion = MockInsertion(); insertion.result = .attempted
        let session = SessionController(audio: audio, pipeline: MockPipeline(), insertion: insertion)
        session.begin(key: "test", preferences: Preferences()); await waitFor(.recording, session); session.stop(); await waitFor(.attempted, session)
        #expect(!(session.canRetryInsertion)); #expect(session.message.localizedCaseInsensitiveContains("check your destination"))
    }
    @Test @MainActor func testRawModeRoutesUnmodifiedTranscript() async {
        let audio = MockAudio(); let insertion = MockInsertion(); var prefs = Preferences(); prefs.cleanup = false
        let session = SessionController(audio: audio, pipeline: MockPipeline(), insertion: insertion)
        session.begin(key: "test", preferences: prefs); await waitFor(.recording, session); session.stop(); await waitFor(.success, session)
        #expect(insertion.inserted ==  ["hello world"])
    }
    @Test @MainActor func testMaximumDurationStopsRecording() async {
        let audio = MockAudio(); let session = SessionController(audio: audio, pipeline: MockPipeline(), insertion: MockInsertion())
        session.begin(key: "test", preferences: Preferences()); await waitFor(.recording, session)
        audio.elapsed = 180; session.tick(); #expect(audio.stops ==  1); await waitFor(.success, session)
    }
    @Test @MainActor func testDismissDoesNotStopLiveRecording() async {
        let audio = MockAudio(); let session = SessionController(audio: audio, pipeline: MockPipeline(), insertion: MockInsertion())
        session.begin(key: "test", preferences: Preferences()); await waitFor(.recording, session); session.dismiss()
        #expect(session.state ==  .recording); session.cancel()
    }
    @Test @MainActor func testCancelDuringGeneration() async {
        let audio = MockAudio(); let insertion = MockInsertion()
        let session = SessionController(audio: audio, pipeline: MockPipeline(cleanDelay: .seconds(1)), insertion: insertion)
        session.begin(key: "test", preferences: Preferences()); await waitFor(.recording, session); session.stop(); await waitFor(.generating, session)
        session.cancel(); try? await Task.sleep(for: .milliseconds(20))
        #expect(session.state == .cancelled); #expect(insertion.inserts == 0)
        #expect(!FileManager.default.fileExists(atPath: audio.url.path))
    }
    @Test @MainActor func testCleanupFailureKeepsRawTranscript() async {
        let audio = MockAudio(); let insertion = MockInsertion()
        let session = SessionController(audio: audio, pipeline: MockPipeline(cleanError: .malformedResponse), insertion: insertion)
        session.begin(key: "test", preferences: Preferences()); await waitFor(.recording, session); session.stop(); await waitFor(.success, session)
        #expect(session.rawText == "hello world"); #expect(session.finalText == "hello world")
        #expect(insertion.inserted == ["hello world"])
        #expect(session.message.contains("text cleanup unavailable"))
    }
    @Test @MainActor func testTextServiceOutagesDoNotBlockRecognizedSpeechDelivery() async {
        for failure in [FlowError.service(503), .rateLimited, .network, .timeout] {
            let audio = MockAudio(); let insertion = MockInsertion()
            let session = SessionController(audio: audio, pipeline: MockPipeline(cleanError: failure), insertion: insertion)
            session.begin(key: "test", preferences: Preferences()); await waitFor(.recording, session)
            session.stop(); await waitFor(.success, session)
            #expect(session.rawText == "hello world" && session.finalText == "hello world")
            #expect(insertion.inserted == ["hello world"])
            #expect(session.message.contains("text cleanup unavailable"))
            session.retryInsertion(); #expect(insertion.inserts == 1)
        }
    }
    @Test @MainActor func testShutdownWaitsForAudioCleanup() async {
        let audio = MockAudio(); let insertion = MockInsertion()
        let session = SessionController(audio: audio, pipeline: MockPipeline(delay: .milliseconds(100), ignoreCancellation: true), insertion: insertion)
        session.begin(key: "test", preferences: Preferences()); await waitFor(.recording, session); session.stop()
        try? await Task.sleep(for: .milliseconds(10)); await session.shutdown()
        #expect(insertion.inserts == 0); #expect(!FileManager.default.fileExists(atPath: audio.url.path))
    }
}
