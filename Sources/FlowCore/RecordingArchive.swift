import Foundation

public struct ArchivedSegment: Codable, Sendable, Identifiable {
    public var id: String
    public var audio: String
    public var rawFile: String?
    public var finalFile: String?
    public var attempts = 0
    public var status = "pending"
    public var error: String?
}
public struct RecordingManifest: Codable, Sendable {
    public var version = 1
    public var created = Date()
    public var finished = false
    public var interrupted = false
    public var preferences: Preferences
    public var segments: [ArchivedSegment] = []
}
public actor RecordingArchive {
    public let directory: URL
    private var manifest: RecordingManifest
    public init(directory: URL, preferences: Preferences) throws {
        self.directory = directory
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent("session.json").path) {
            manifest = try JSONDecoder().decode(RecordingManifest.self, from: Data(contentsOf: directory.appendingPathComponent("session.json")))
            guard manifest.version == 1 else { throw FlowError.storage }
            for segment in manifest.segments {
                for filename in [segment.audio, segment.rawFile, segment.finalFile].compactMap({ $0 }) {
                    guard filename == URL(fileURLWithPath: filename).lastPathComponent, !filename.hasPrefix("."), filename.hasPrefix("segment-") else { throw FlowError.storage }
                }
                guard segment.id == URL(fileURLWithPath: segment.audio).deletingPathExtension().lastPathComponent else { throw FlowError.storage }
            }
        } else {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            manifest = RecordingManifest(preferences: preferences)
            try Self.write(JSONEncoder().encode(manifest), to: directory.appendingPathComponent("session.json"))
        }
    }
    public static var root: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Flow/Recordings") }
    private static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private func save() throws { try Self.write(JSONEncoder().encode(manifest), to: directory.appendingPathComponent("session.json")) }
    public func enqueue(_ urls: [URL]) throws {
        for url in urls {
            guard url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL,
                  url.lastPathComponent.hasPrefix("segment-"), url.pathExtension == "wav" else { throw FlowError.storage }
            if !manifest.segments.contains(where: { $0.audio == url.lastPathComponent }) {
                manifest.segments.append(ArchivedSegment(id: url.deletingPathExtension().lastPathComponent, audio: url.lastPathComponent))
            }
        }
        if !processing { manifest.segments.sort { $0.audio < $1.audio } }
        try save()
    }
    public func processPending(pipeline: any TextPipeline, key: String) async throws -> Int {
        // Actor reentrancy is safe: only one caller processes this archive at a time via processing flag.
        guard !processing else { return 0 }; processing = true
        defer { processing = false; manifest.segments.sort { $0.audio < $1.audio }; try? save() }
        var completed = 0
        for index in manifest.segments.indices where manifest.segments[index].status != "complete" {
            try Task.checkCancellation()
            manifest.segments[index].attempts += 1
            manifest.segments[index].status = "processing"; try save()
            do {
                let segment = manifest.segments[index]
                let rawURL = directory.appendingPathComponent(segment.id + ".raw.txt")
                let finalURL = directory.appendingPathComponent(segment.id + ".txt")
                let raw: String
                if FileManager.default.fileExists(atPath: rawURL.path) { raw = try String(contentsOf: rawURL, encoding: .utf8) }
                else if FileManager.default.fileExists(atPath: directory.appendingPathComponent(segment.id + ".silent").path) {
                    raw = ""
                    try Self.write(Data(), to: rawURL)
                } else {
                    raw = try await pipeline.transcribe(audio: directory.appendingPathComponent(segment.audio), key: key, preferences: manifest.preferences)
                    try Self.write(Data(raw.utf8), to: rawURL)
                }
                manifest.segments[index].rawFile = rawURL.lastPathComponent; try save()
                let final: String
                do { final = raw.isEmpty ? "" : try await pipeline.clean(text: raw, key: key, preferences: manifest.preferences) }
                catch is CancellationError { throw CancellationError() }
                catch { final = try DictationFormatting.finalize(raw) }
                try Task.checkCancellation()
                try Self.write(Data(final.utf8), to: finalURL)
                manifest.segments[index].finalFile = finalURL.lastPathComponent
                manifest.segments[index].status = "complete"; manifest.segments[index].error = nil
                try save(); completed += 1
            } catch {
                manifest.segments[index].status = "pending"
                manifest.segments[index].error = (error as? FlowError ?? .network).localizedDescription
                try save(); throw error
            }
        }
        try export(); return completed
    }
    private var processing = false
    public func finish(interrupted: Bool = false) throws {
        manifest.finished = true; manifest.interrupted = interrupted; try save(); try export()
    }
    public func snapshot() -> RecordingManifest { manifest }
    public func preview() throws -> String {
        let completed = manifest.segments.filter { $0.status == "complete" }.suffix(3)
        return try completed.compactMap { $0.finalFile }.map { try String(contentsOf: directory.appendingPathComponent($0), encoding: .utf8) }.joined(separator: "\n\n")
    }
    public func export() throws {
        let temporary = directory.appendingPathComponent(".transcript-" + UUID().uuidString)
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw FlowError.storage }
        defer { try? FileManager.default.removeItem(at: temporary) }
        let handle = try FileHandle(forWritingTo: temporary); defer { try? handle.close() }
        for segment in manifest.segments.sorted(by: { $0.audio < $1.audio }) {
            if let filename = segment.finalFile { try handle.write(contentsOf: Data(contentsOf: directory.appendingPathComponent(filename))); try handle.write(contentsOf: Data("\n\n".utf8)) }
            else { try handle.write(contentsOf: Data("[Pending transcription: \(segment.id)]\n\n".utf8)) }
        }
        try handle.synchronize()
        let destination = directory.appendingPathComponent("Transcript.txt")
        if FileManager.default.fileExists(atPath: destination.path) { _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary) }
        else { try FileManager.default.moveItem(at: temporary, to: destination) }
    }
    public static func recoverSegments(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "wav" && $0.lastPathComponent.hasPrefix("segment-") }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
