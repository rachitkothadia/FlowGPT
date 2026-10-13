import AVFoundation
import AudioToolbox
import CoreAudio
import CoreMedia
import Foundation
import FlowCore

private final class NativeMicSamples: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var chunks: [Data] = []
    private var bytes = 0
    private var peak = 0.0
    private var firstFrame: TimeInterval?
    private var failure: String?
    private var accepting = true
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format),
              asbd.pointee.mSampleRate == 16_000, asbd.pointee.mChannelsPerFrame == 1,
              asbd.pointee.mBitsPerChannel == 32, asbd.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { fail("The microphone did not deliver the requested 16 kHz mono float format"); return }
        let length = CMBlockBufferGetDataLength(block)
        guard length > 0, length % 4 == 0 else { return }
        var data = Data(count: length)
        let status = data.withUnsafeMutableBytes { pointer in
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: pointer.baseAddress!)
        }
        guard status == kCMBlockBufferNoErr else { fail("Microphone frame copy failed"); return }
        let count = length / 4
        let sum = data.withUnsafeBytes { pointer -> Double in
            pointer.bindMemory(to: Float.self).reduce(0) { $0 + Double($1 * $1) }
        }
        lock.lock(); defer { lock.unlock() }
        guard accepting else { return }
        // 30 seconds of unsent 16 kHz mono frames. Never discard old speech.
        guard bytes + data.count <= 16_000 * 4 * 30 else { failure = "The connection did not accept microphone audio within 30 seconds"; accepting = false; return }
        if firstFrame == nil { firstFrame = ProcessInfo.processInfo.systemUptime }
        peak = min(1, sqrt(sum / Double(count)) * 6)
        chunks.append(data); bytes += data.count
    }
    func fail(_ message: String) { lock.lock(); failure = message; accepting = false; lock.unlock() }
    func snapshot() -> (Int, Double, TimeInterval?, String?) { lock.lock(); defer { lock.unlock() }; return (bytes, peak, firstFrame, failure) }
    func peek() -> Data? { lock.lock(); defer { lock.unlock() }; return chunks.first }
    func acknowledge() { lock.lock(); defer { lock.unlock() }; if !chunks.isEmpty { bytes -= chunks.removeFirst().count } }
    func freeze() { lock.lock(); accepting = false; peak = 0; lock.unlock() }
}

/// Captures locally without waiting for DOM, JavaScript, network or WebKit audio
/// permissions. Never changes the system's input device or output volume.
@MainActor final class NativeBrowserMicrophone {
    private var capture: AVCaptureSession?
    private var samples: NativeMicSamples?
    private var observer: NSObjectProtocol?
    private(set) var inputName = "System microphone"
    private(set) var startMilliseconds = 0.0
    private var began = 0.0
    var isCapturing: Bool { capture?.isRunning == true }
    var firstFrameMilliseconds: Double? { samples?.snapshot().2.map { ($0 - began) * 1_000 } }
    var level: Double { samples?.snapshot().1 ?? 0 }
    var pendingBytes: Int { samples?.snapshot().0 ?? 0 }
    var failure: String? { samples?.snapshot().3 }
    func start() throws {
        guard !isCapturing else { throw FlowError.recording }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { throw FlowError.microphone }
        cancel(); began = ProcessInfo.processInfo.systemUptime
        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone], mediaType: .audio, position: .unspecified).devices
        let builtin = Self.builtinInputUID()
        guard let device = devices.first(where: { $0.uniqueID == builtin }) ?? AVCaptureDevice.default(for: .audio) else { throw FlowError.microphone }
        inputName = device.localizedName
        let value = AVCaptureSession(), input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureAudioDataOutput(), sink = NativeMicSamples()
        output.audioSettings = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false]
        output.setSampleBufferDelegate(sink, queue: DispatchQueue(label: "in.vardaan.flow.capture", qos: .userInteractive))
        value.beginConfiguration()
        guard value.canAddInput(input), value.canAddOutput(output) else { value.commitConfiguration(); throw FlowError.recording }
        value.addInput(input); value.addOutput(output); value.commitConfiguration()
        value.startRunning()
        guard value.isRunning else { value.stopRunning(); throw FlowError.recording }
        capture = value; samples = sink
        startMilliseconds = (ProcessInfo.processInfo.systemUptime - began) * 1_000
        observer = NotificationCenter.default.addObserver(forName: .AVCaptureSessionRuntimeError, object: value, queue: nil) { _ in sink.fail("Microphone capture was interrupted; captured audio was not silently replaced") }
    }
    func peek() -> Data? { samples?.peek() }
    func acknowledge() { samples?.acknowledge() }
    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
        samples?.freeze()
        capture?.stopRunning(); capture = nil
    }
    func cancel() { stop(); samples = nil }
    private static func builtinInputUID() -> String? {
        var property = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size) == noErr else { return nil }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, &devices) == noErr else { return nil }
        for device in devices {
            property.mSelector = kAudioDevicePropertyTransportType
            property.mScope = kAudioObjectPropertyScopeGlobal
            var transport: UInt32 = 0; size = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &transport) == noErr, transport == kAudioDeviceTransportTypeBuiltIn else { continue }
            property.mSelector = kAudioDevicePropertyStreams; property.mScope = kAudioDevicePropertyScopeInput
            guard AudioObjectGetPropertyDataSize(device, &property, 0, nil, &size) == noErr, size > 0 else { continue }
            property.mSelector = kAudioDevicePropertyDeviceUID; property.mScope = kAudioObjectPropertyScopeGlobal
            let name = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
            name.initialize(to: nil)
            defer { name.deinitialize(count: 1); name.deallocate() }
            size = UInt32(MemoryLayout<CFString?>.size)
            _ = AudioObjectGetPropertyData(device, &property, 0, nil, &size, name)
            return name.pointee as String?
        }
        return nil
    }
}
