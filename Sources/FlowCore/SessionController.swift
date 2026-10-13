import Foundation
import Observation

@MainActor public protocol AudioCapture: AnyObject {
    func configure(_ preferences: Preferences)
    func start() async throws
    func stop() throws -> URL
    func cancel()
    var level: Double { get }
    var elapsed: TimeInterval { get }
}
public extension AudioCapture { func configure(_ preferences: Preferences) {} }
@MainActor public protocol SegmentedAudioCapture: AudioCapture {
    var recordingDirectory: URL? { get }
    func takeSegments() throws -> [URL]
    func finishSegments() throws -> [URL]
}
@MainActor public protocol TextInsertion: AnyObject {
    func captureTarget()
    func insert(_ text: String, preserveClipboard: Bool) async throws -> InsertionOutcome
    func reset()
}
@MainActor @Observable public final class SessionController {
    public private(set) var state: SessionState = .idle
    public private(set) var message = "Ready to dictate"
    public private(set) var rawText = ""
    public private(set) var finalText = ""
    public private(set) var level: Double = 0
    public private(set) var elapsed: TimeInterval = 0
    public private(set) var canRetryInsertion = false
    public private(set) var isLocalPreview = false
    public private(set) var recordingDirectory: URL?
    public private(set) var pendingSegments = 0
    public var onResult: ((DictationResult) -> Void)?
    public var onState: ((SessionState) -> Void)?
    private let audio: any AudioCapture
    private let pipeline: any TextPipeline
    private let insertion: any TextInsertion
    private var work: Task<Void, Never>?
    private var generation = UUID()
    private var settings = Preferences()
    private var key = ""
    private var insertIntoTarget = true
    private var archive: RecordingArchive?
    private var segmentWork: Task<Void, Never>?
    private var checkpointWork: Task<Void, Never>?
    private var nextSegmentCheck = Date.distantPast
    public init(audio: any AudioCapture, pipeline: any TextPipeline, insertion: any TextInsertion) { self.audio = audio; self.pipeline = pipeline; self.insertion = insertion }
    private func set(_ state: SessionState, _ message: String) { self.state = state; self.message = message; onState?(state) }
    public func showTip() {
        guard !state.busy else { return }
        set(.tip, "Try using Flow in another app!")
    }
    public func toggle(key: String, preferences: Preferences) {
        if state == .recording { stop(); return }
        guard !state.busy else { return }
        begin(key: key, preferences: preferences)
    }
    public func begin(key: String, preferences: Preferences, insertIntoTarget: Bool = true) {
        guard !state.busy else { return }
        guard !key.isEmpty else { set(.error, FlowError.missingKey.localizedDescription); return }
        work?.cancel(); generation = UUID(); let session = generation
        settings = preferences; self.key = key; rawText = ""; finalText = ""; canRetryInsertion = false
        self.insertIntoTarget = insertIntoTarget
        isLocalPreview = !insertIntoTarget
        archive = nil; recordingDirectory = nil; pendingSegments = 0
        audio.configure(preferences)
        if insertIntoTarget { insertion.captureTarget() } else { insertion.reset() }
        set(.starting, "Preparing microphone…")
        work = Task { [weak self] in
            guard let self else { return }
            do {
                try await audio.start()
                guard generation == session, !Task.isCancelled else { return }
                if settings.isContinuous, let capture = audio as? any SegmentedAudioCapture, let directory = capture.recordingDirectory {
                    recordingDirectory = directory
                    archive = try RecordingArchive(directory: directory, preferences: settings)
                } else if settings.isContinuous { audio.cancel(); throw FlowError.recording }
                set(.recording, "Listening")
            } catch {
                guard generation == session else { return }
                audio.cancel(); fail(error)
            }
        }
    }
    public func tick() {
        guard state == .recording else { return }
        level = audio.level; elapsed = audio.elapsed
        if settings.isContinuous {
            if segmentWork == nil && Date() >= nextSegmentCheck { processSegments() }
        } else if elapsed >= 180 { stop() }
    }
    private func processSegments() {
        guard let archive, let capture = audio as? any SegmentedAudioCapture else { return }
        let session = generation
        let urls: [URL]
        do { urls = try capture.takeSegments() }
        catch { stop(); return }
        nextSegmentCheck = Date().addingTimeInterval(5)
        segmentWork = Task { [weak self] in
            guard let self else { return }
            defer { if generation == session { segmentWork = nil } }
            do {
                try await archive.enqueue(urls)
                _ = try await archive.processPending(pipeline: pipeline, key: key)
                let snapshot = await archive.snapshot()
                guard generation == session else { return }
                pendingSegments = snapshot.segments.filter { $0.status != "complete" }.count
                finalText = try await archive.preview()
            } catch {
                guard generation == session else { return }
                nextSegmentCheck = Date().addingTimeInterval(60)
                let snapshot = await archive.snapshot()
                pendingSegments = snapshot.segments.filter { $0.status != "complete" }.count
                message = "Recording continues. Audio is saved; transcription will retry."
            }
        }
    }
    private func finishContinuous() {
        guard let archive, let capture = audio as? any SegmentedAudioCapture else { return }
        let session = generation
        let segments: [URL]
        do { segments = try capture.finishSegments() }
        catch { fail(error); return }
        let pending = segmentWork
        set(.transcribing, "Finishing the saved transcript…")
        work = Task { [weak self] in
            guard let self else { return }
            await pending?.value
            do {
                try Task.checkCancellation()
                try await archive.enqueue(segments)
                try await archive.finish()
                _ = try await archive.processPending(pipeline: pipeline, key: key)
                guard generation == session else { return }
                finalText = try await archive.preview(); key = ""; pendingSegments = 0
                set(.success, "Transcript saved in your recording folder")
            } catch {
                guard generation == session else { return }
                try? await archive.finish()
                let snapshot = await archive.snapshot()
                pendingSegments = snapshot.segments.filter { $0.status != "complete" }.count
                fail(error)
            }
        }
    }
    public func recoverRecording(at directory: URL, key: String, preferences: Preferences) {
        guard !state.busy, !key.isEmpty else { return }
        generation = UUID(); let session = generation
        recordingDirectory = directory
        set(.transcribing, "Recovering saved audio…")
        work = Task { [weak self] in
            guard let self else { return }
            do {
                let recovered = try RecordingArchive(directory: directory, preferences: preferences)
                try await recovered.enqueue(RecordingArchive.recoverSegments(in: directory))
                try await recovered.finish(interrupted: true)
                _ = try await recovered.processPending(pipeline: pipeline, key: key)
                guard generation == session else { return }
                finalText = try await recovered.preview(); pendingSegments = 0
                set(.success, "Recovered transcript saved")
            } catch { guard generation == session else { return }; fail(error) }
        }
    }
    public func stop() {
        guard state == .recording else { return }
        if settings.isContinuous { finishContinuous(); return }
        let session = generation
        do {
            let url = try audio.stop(); set(.transcribing, "Transcribing…")
            work = Task { [weak self] in
                guard let self else { return }
                defer {
                    if self.generation == session { self.key = "" }
                    do { try FileManager.default.removeItem(at: url) }
                    catch { if self.generation == session, FileManager.default.fileExists(atPath: url.path) { self.message += " Temporary audio cleanup failed; restart Flow to retry cleanup." } }
                }
                do {
                    let raw = try await pipeline.transcribe(audio: url, key: key, preferences: settings)
                    try Task.checkCancellation(); guard generation == session else { return }
                    rawText = raw
                    if settings.cleanup { set(.generating, "Refining your words…") }
                    let final: String
                    var cleanupUnavailable = false
                    do { final = try await pipeline.clean(text: raw, key: key, preferences: settings) }
                    catch is CancellationError { throw CancellationError() }
                    catch FlowError.cancelled { throw CancellationError() }
                    catch let error as URLError where error.code == .cancelled { throw CancellationError() }
                    catch {
                        // Optional formatting must not block delivery of successfully recognized speech.
                        // No second insertion or API retry is performed; use the complete source.
                        try Task.checkCancellation()
                        final = try DictationFormatting.finalize(raw)
                        cleanupUnavailable = true
                    }
                    try Task.checkCancellation(); guard generation == session else { return }
                    finalText = try TextValidation.validate(final)
                    onResult?(DictationResult(raw: rawText, final: finalText, mode: settings.mode))
                    if !insertIntoTarget {
                        set(.success, "Transcript ready in Flow. Start in another app to insert there automatically." + (cleanupUnavailable ? " Text cleanup was unavailable; original transcript preserved." : ""))
                        return
                    }
                    canRetryInsertion = true; set(.inserting, "Inserting…")
                    let outcome = try await insertion.insert(finalText, preserveClipboard: settings.preserveClipboard)
                    try Task.checkCancellation(); guard generation == session else { return }
                    canRetryInsertion = false
                    switch outcome {
                    case .confirmed: set(.success, cleanupUnavailable ? "Inserted original transcript · text cleanup unavailable" : "Inserted")
                    case .attempted: set(.attempted, "Insertion could not be verified. Check your destination" + (cleanupUnavailable ? " · text cleanup unavailable" : ""))
                    }
                } catch {
                    guard generation == session else { return }
                    fail(error)
                }
            }
        } catch { audio.cancel(); fail(error) }
    }
    public func retryInsertion() {
        guard canRetryInsertion, !state.busy, !finalText.isEmpty else { return }
        let session = generation; set(.inserting, "Retrying insertion…")
        work = Task { [weak self] in
            guard let self else { return }
            do {
                let outcome = try await insertion.insert(finalText, preserveClipboard: settings.preserveClipboard)
                guard generation == session, !Task.isCancelled else { return }
                canRetryInsertion = false
                set(outcome == .confirmed ? .success : .attempted, outcome == .confirmed ? "Inserted" : "Insertion could not be verified. Check your destination")
            } catch { guard generation == session else { return }; fail(error) }
        }
    }
    public func cancel() {
        if settings.isContinuous, state.busy, let archive, let capture = audio as? any SegmentedAudioCapture {
            let segments = (try? capture.finishSegments()) ?? []
            checkpointWork = Task { try? await archive.enqueue(segments); try? await archive.finish(interrupted: true) }
        }
        segmentWork?.cancel(); segmentWork = nil
        generation = UUID(); work?.cancel(); work = nil; audio.cancel(); insertion.reset(); canRetryInsertion = false
        level = 0; elapsed = 0; key = ""; set(.cancelled, "Cancelled")
    }
    public func shutdown() async {
        let pending = work, segmentPending = segmentWork
        cancel()
        await pending?.value; await segmentPending?.value; await checkpointWork?.value
    }
    public func dismiss() { guard !state.busy else { return }; set(.idle, "Ready to dictate") }
    private func fail(_ error: Error) {
        if error is CancellationError { set(.cancelled, "Cancelled"); return }
        set(.error, (error as? FlowError ?? .network).localizedDescription)
    }
}
