import Foundation
import AVFoundation
import FlowCore

// The audio tap writes PCM locally; it never waits for network, model or UI work.
private final class SegmentSink: @unchecked Sendable {
    private let lock = NSLock()
    let directory: URL
    private let format: AVAudioFormat
    private var writer: AVAudioFile?
    private var activeURL: URL?
    private var index = 0
    private var frames: AVAudioFramePosition = 0
    private var totalFrames: AVAudioFramePosition = 0
    private var ready: [URL] = []
    private var failure: Error?
    private var rms = 0.0
    private var peak = Float(0)
    private var closed = false
    init(directory: URL, format: AVAudioFormat) throws {
        self.directory = directory; self.format = format
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try open()
    }
    private func open() throws {
        let url = directory.appendingPathComponent(String(format: "active-%06d.wav", index))
        writer = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false], commonFormat: .pcmFormatFloat32, interleaved: false)
        activeURL = url; frames = 0; peak = 0
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private func finalize() throws {
        writer = nil
        guard let activeURL else { return }
        if frames > 0 {
            let completed = directory.appendingPathComponent(String(format: "segment-%06d.wav", index))
            try FileManager.default.moveItem(at: activeURL, to: completed); ready.append(completed); index += 1
            if peak < 0.000001 {
                let marker = completed.deletingPathExtension().appendingPathExtension("silent")
                try Data().write(to: marker, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
            }
        } else { try FileManager.default.removeItem(at: activeURL) }
        self.activeURL = nil
    }
    func accept(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard !closed, failure == nil, buffer.frameLength > 0 else { return }
        do {
            guard let samples = buffer.floatChannelData?[0] else { throw FlowError.recording }
            var sum = 0.0
            for i in 0..<Int(buffer.frameLength) { sum += Double(samples[i] * samples[i]); peak = max(peak, abs(samples[i])) }
            rms = sqrt(sum / Double(buffer.frameLength))
            try writer?.write(from: buffer)
            frames += Int64(buffer.frameLength); totalFrames += Int64(buffer.frameLength)
            // Prefer a quiet boundary after 45s; cap at 60s. Nonoverlapping PCM avoids
            // fuzzy text deduplication deleting intentionally repeated lecture words.
            if frames >= 960_000 || (frames >= 720_000 && rms < 0.008) { try finalize(); try open() }
        } catch { failure = error }
    }
    func fail(_ error: Error) { lock.lock(); defer { lock.unlock() }; failure = error }
    func snapshot() -> (Double, Double, Bool) {
        lock.lock(); defer { lock.unlock() }; return (Double(totalFrames) / 16_000, min(1, rms * 5), failure != nil)
    }
    func drain() throws -> [URL] {
        lock.lock(); defer { lock.unlock() }
        if let failure { throw failure }; let result = ready; ready = []; return result
    }
    func finish() throws -> [URL] {
        lock.lock(); defer { lock.unlock() }
        closed = true
        // Finalize captured audio even when a later write failed, keeping recovery files.
        try finalize()
        if let failure { throw failure }; let result = ready; ready = []; return result
    }
}
private final class ConverterSink: @unchecked Sendable {
    let converter: AVAudioConverter
    let format: AVAudioFormat
    let sink: SegmentSink
    init(converter: AVAudioConverter, format: AVAudioFormat, sink: SegmentSink) { self.converter = converter; self.format = format; self.sink = sink }
    func accept(_ input: AVAudioPCMBuffer) {
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * format.sampleRate / input.format.sampleRate)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { sink.fail(FlowError.recording); return }
        let supply = BufferSupply(input)
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            supply.next(status)
        }
        if let error { sink.fail(error) } else { sink.accept(output) }
    }
}
private final class BufferSupply: @unchecked Sendable {
    private let lock = NSLock()
    private let buffer: AVAudioPCMBuffer
    private var supplied = false
    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioPCMBuffer? {
        lock.lock(); defer { lock.unlock() }
        if supplied { status.pointee = .noDataNow; return nil }
        supplied = true; status.pointee = .haveData; return buffer
    }
}
@MainActor final class ContinuousRecorder: SegmentedAudioCapture {
    private var engine: AVAudioEngine?
    private var sink: SegmentSink?
    private var configurationObserver: NSObjectProtocol?
    private(set) var recordingDirectory: URL?
    func start() async throws {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .notDetermined {
            guard await AVCaptureDevice.requestAccess(for: .audio) else { throw FlowError.microphone }
        } else if status != .authorized { throw FlowError.microphone }
        try Task.checkCancellation()
        let directory = RecordingArchive.root.appendingPathComponent(UUID().uuidString)
        let engine = AVAudioEngine(), input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inputFormat, to: format) else { throw FlowError.recording }
        let sink = try SegmentSink(directory: directory, format: format)
        let adapter = ConverterSink(converter: converter, format: format, sink: sink)
        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { @Sendable buffer, _ in adapter.accept(buffer) }
        do { engine.prepare(); try engine.start() }
        catch { input.removeTap(onBus: 0); _ = try? sink.finish(); throw FlowError.recording }
        self.engine = engine; self.sink = sink; recordingDirectory = directory
        configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { _ in
            // Stop accepting frames from a changed device format; retain the original
            // audio instead of pretending that the uninterrupted lecture was captured.
            sink.fail(FlowError.recording)
        }
    }
    var elapsed: TimeInterval { sink?.snapshot().0 ?? 0 }
    var level: Double { sink?.snapshot().1 ?? 0 }
    func takeSegments() throws -> [URL] { try sink?.drain() ?? [] }
    func finishSegments() throws -> [URL] {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver); self.configurationObserver = nil }
        engine?.inputNode.removeTap(onBus: 0); engine?.stop(); engine = nil
        defer { sink = nil }; return try sink?.finish() ?? []
    }
    func stop() throws -> URL {
        guard let last = try finishSegments().last else { throw FlowError.tooShort }; return last
    }
    func cancel() { _ = try? finishSegments() } // Durable recordings remain recoverable.
}
@MainActor final class AdaptiveRecorder: SegmentedAudioCapture {
    private let short = MicrophoneRecorder()
    private let long = ContinuousRecorder()
    private let system = SystemAudioRecorder()
    private var continuous = false
    private var computerAudio = false
    private var segmented: any SegmentedAudioCapture { computerAudio ? system : long }
    func configure(_ preferences: Preferences) { continuous = preferences.isContinuous; computerAudio = preferences.audioSource == "Computer audio" }
    func start() async throws { if continuous { try await segmented.start() } else { try await short.start() } }
    func stop() throws -> URL { if continuous { return try segmented.stop() }; return try short.stop() }
    func cancel() { if continuous { segmented.cancel() } else { short.cancel() } }
    var elapsed: TimeInterval { continuous ? segmented.elapsed : short.elapsed }
    var level: Double { continuous ? segmented.level : short.level }
    var recordingDirectory: URL? { continuous ? segmented.recordingDirectory : nil }
    func takeSegments() throws -> [URL] { continuous ? try segmented.takeSegments() : [] }
    func finishSegments() throws -> [URL] { try segmented.finishSegments() }
}

// Offline continuity check uses the production PCM writer. It simulates sample duration,
// not elapsed recording time, and does not request microphone access or upload audio.
enum ContinuousAudioDiagnostics {
    static func verify(hours: Int) throws -> String {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("flow25-audio-check-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000), let samples = buffer.floatChannelData?[0] else { throw FlowError.recording }
        let sink = try SegmentSink(directory: directory, format: format)
        buffer.frameLength = 48_000
        for i in 0..<48_000 { samples[i] = 0.02 }
        var urls: [URL] = []
        for i in 0..<(hours * 1200) {
            sink.accept(buffer)
            if i % 20 == 0 { urls += try sink.drain() }
        }
        urls += try sink.finish()
        var frames: Int64 = 0
        for url in urls {
            let file = try AVAudioFile(forReading: url)
            guard file.fileFormat.sampleRate == 16_000, file.fileFormat.channelCount == 1 else { throw FlowError.recording }
            frames += file.length
        }
        let expected = Int64(hours) * 3600 * 16_000
        guard frames == expected, urls.count == hours * 60 else { throw FlowError.recording }
        return "\(hours)h PCM-duration simulation: PASS · \(urls.count) segments · \(frames) frames · no dropped/duplicated PCM frames"
    }
}

import ScreenCaptureKit
import CoreMedia

private final class SystemAudioOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let sink: SegmentSink
    private var adapter: ConverterSink?
    private var sourceFormat: AVAudioFormat?
    init(sink: SegmentSink) { self.sink = sink }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio, sampleBuffer.isValid, let description = sampleBuffer.formatDescription else { return }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        let count = sampleBuffer.numSamples
        guard count > 0, count <= 100000, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else { return }
        buffer.frameLength = AVAudioFrameCount(count)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(count), into: buffer.mutableAudioBufferList)
        guard status == noErr else { sink.fail(FlowError.recording); return }
        if sourceFormat != format {
            guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
                  let converter = AVAudioConverter(from: format, to: target) else { sink.fail(FlowError.recording); return }
            adapter = ConverterSink(converter: converter, format: target, sink: sink); sourceFormat = format
        }
        adapter?.accept(buffer)
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { sink.fail(error) }
}
@MainActor private final class SystemAudioRecorder: SegmentedAudioCapture {
    private var stream: SCStream?
    private var output: SystemAudioOutput?
    private var sink: SegmentSink?
    private let queue = DispatchQueue(label: "in.vardaan.flow.system-audio")
    private(set) var recordingDirectory: URL?
    func start() async throws {
        // This requests only ScreenCaptureKit's separate system-audio/screen grant.
        // Accessibility and Input Monitoring are never reset or changed here.
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        guard let display = content.displays.first,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false) else { throw FlowError.recording }
        let directory = RecordingArchive.root.appendingPathComponent(UUID().uuidString)
        let sink = try SegmentSink(directory: directory, format: format)
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true; configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000; configuration.channelCount = 2
        configuration.width = 2; configuration.height = 2; configuration.queueDepth = 3
        configuration.minimumFrameInterval = CMTime(seconds: 1, preferredTimescale: 1)
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let output = SystemAudioOutput(sink: sink)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: output)
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: queue)
        do { try await stream.startCapture() }
        catch { _ = try? sink.finish(); throw error }
        self.sink = sink; self.output = output; self.stream = stream; recordingDirectory = directory
    }
    var elapsed: TimeInterval { sink?.snapshot().0 ?? 0 }
    var level: Double { sink?.snapshot().1 ?? 0 }
    func takeSegments() throws -> [URL] { try sink?.drain() ?? [] }
    func finishSegments() throws -> [URL] {
        let stream = self.stream
        self.stream = nil
        if let stream, let output { try? stream.removeStreamOutput(output, type: .audio); stream.stopCapture { _ in } }
        // All callbacks arriving after this point are ignored by the closed sink.
        defer { sink = nil; output = nil }
        return try sink?.finish() ?? []
    }
    func stop() throws -> URL { guard let last = try finishSegments().last else { throw FlowError.tooShort }; return last }
    func cancel() { _ = try? finishSegments() }
}
