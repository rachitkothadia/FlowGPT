import Foundation
import Testing
@testable import FlowCore

struct RecordingArchiveTests {
    @Test func archiveRetainsAudioAndResumesAfterFailure() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let audio = directory.appendingPathComponent("segment-000000.wav")
        let archive = try RecordingArchive(directory: directory, preferences: Preferences())
        try Data([1, 2]).write(to: audio); try await archive.enqueue([audio])
        do { _ = try await archive.processPending(pipeline: ArchivePipeline(fail: true), key: "test"); Issue.record("Expected failure") } catch {}
        #expect(FileManager.default.fileExists(atPath: audio.path))
        #expect(await archive.snapshot().segments.first?.status == "pending")
        let reopened = try RecordingArchive(directory: directory, preferences: Preferences())
        #expect(try await reopened.processPending(pipeline: ArchivePipeline(), key: "test") == 1)
        #expect(try await reopened.processPending(pipeline: ArchivePipeline(), key: "test") == 0)
        #expect(try String(contentsOf: directory.appendingPathComponent("Transcript.txt"), encoding: .utf8) == "Exact transcript\n\n")
    }
    @Test func tenHourQueueSimulationOrdersSixHundredSegments() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = try RecordingArchive(directory: directory, preferences: Preferences())
        var urls: [URL] = []
        for i in 0..<600 {
            let url = directory.appendingPathComponent(String(format: "segment-%06d.wav", i))
            try Data([1]).write(to: url); urls.append(url)
        }
        try await archive.enqueue(urls.reversed())
        #expect(try await archive.processPending(pipeline: ArchivePipeline(), key: "test") == 600)
        let snapshot = await archive.snapshot()
        #expect(snapshot.segments.first?.id == "segment-000000")
        #expect(snapshot.segments.last?.id == "segment-000599")
        #expect(snapshot.segments.allSatisfy { $0.status == "complete" })
        // Scheduling/storage simulation only: not a 10-hour audio endurance claim.
    }
}
private struct ArchivePipeline: TextPipeline {
    var fail = false
    func transcribe(audio: URL, key: String, preferences: Preferences) async throws -> String {
        if fail { throw FlowError.network }; return "Exact transcript"
    }
    func clean(text: String, key: String, preferences: Preferences) async throws -> String { text }
}

struct ArchiveIntegrityTests {
    @Test func corruptedArchiveCannotUploadOutsideItsFolder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var manifest = RecordingManifest(preferences: Preferences())
        manifest.segments = [ArchivedSegment(id: "secret", audio: "../secret.wav")]
        try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("session.json"))
        #expect(throws: (any Error).self) { try RecordingArchive(directory: directory, preferences: Preferences()) }
    }
}

struct ArchiveSilenceTests {
    @Test func digitallySilentSegmentNeverCallsSpeechAPI() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = try RecordingArchive(directory: directory, preferences: Preferences())
        let audio = directory.appendingPathComponent("segment-000000.wav")
        try Data([1]).write(to: audio)
        try Data().write(to: directory.appendingPathComponent("segment-000000.silent"))
        try await archive.enqueue([audio])
        #expect(try await archive.processPending(pipeline: ArchivePipeline(fail: true), key: "test") == 1)
        #expect(await archive.snapshot().segments.first?.status == "complete")
    }
}
