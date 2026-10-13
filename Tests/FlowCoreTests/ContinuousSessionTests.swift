import Foundation
import Testing
@testable import FlowCore

@MainActor private final class LectureCapture: SegmentedAudioCapture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var recordingDirectory: URL? { directory }
    var level = 0.2
    var elapsed: TimeInterval = 36000
    var ready: [URL] = []
    var finishes = 0
    func start() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("segment-000000.wav")
        try Data([1]).write(to: url); ready = [url]
    }
    func takeSegments() throws -> [URL] { let result = ready; ready = []; return result }
    func finishSegments() throws -> [URL] { finishes += 1; return try takeSegments() }
    func stop() throws -> URL { directory }
    func cancel() {}
}
struct ContinuousSessionTests {
    @Test @MainActor func tenHoursDoesNotStopOnEverydayLimitAndFinishSaves() async throws {
        let audio = LectureCapture(), insertion = MockInsertion()
        defer { try? FileManager.default.removeItem(at: audio.directory) }
        let session = SessionController(audio: audio, pipeline: MockPipeline(), insertion: insertion)
        var prefs = Preferences(); prefs.continuous = true
        session.begin(key: "test", preferences: prefs)
        for _ in 0..<100 where session.state != .recording { try await Task.sleep(for: .milliseconds(5)) }
        session.tick()
        #expect(session.state == .recording)
        #expect(session.elapsed == 36000)
        session.stop()
        for _ in 0..<100 where session.state.busy { try await Task.sleep(for: .milliseconds(5)) }
        #expect(session.state == .success)
        #expect(insertion.inserts == 0)
        #expect(FileManager.default.fileExists(atPath: audio.directory.appendingPathComponent("Transcript.txt").path))
    }
    @Test @MainActor func shutdownWaitsForDurableLectureCheckpoint() async throws {
        let audio = LectureCapture()
        defer { try? FileManager.default.removeItem(at: audio.directory) }
        let session = SessionController(audio: audio, pipeline: MockPipeline(), insertion: MockInsertion())
        var prefs = Preferences(); prefs.continuous = true
        session.begin(key: "test", preferences: prefs)
        for _ in 0..<100 where session.state != .recording { try await Task.sleep(for: .milliseconds(5)) }
        await session.shutdown()
        let data = try Data(contentsOf: audio.directory.appendingPathComponent("session.json"))
        let manifest = try JSONDecoder().decode(RecordingManifest.self, from: data)
        #expect(manifest.interrupted)
        #expect(manifest.segments.count == 1)
        #expect(FileManager.default.fileExists(atPath: audio.directory.appendingPathComponent("segment-000000.wav").path))
    }
}
