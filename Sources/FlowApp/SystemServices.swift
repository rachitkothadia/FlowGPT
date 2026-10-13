import AppKit
import AVFoundation
@preconcurrency import ApplicationServices
import ServiceManagement
import Observation
import FlowCore

private struct PermissionSnapshot: Sendable {
    let microphone: Bool
    let accessibility: Bool
    let input: Bool
}
@MainActor @Observable final class Permissions {
    private(set) var microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    private(set) var accessibility = AXIsProcessTrusted()
    private(set) var inputMonitoring = CGPreflightListenEventAccess()
    private(set) var needsRestart = false
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var refreshing = false
    func refresh() {
        guard !refreshing, let executable = Bundle.main.executableURL else { return }
        refreshing = true
        Task {
            // A fresh process avoids Core Graphics' cached permission result after a grant/revoke.
            let snapshot = await Task.detached(priority: .utility) { () -> PermissionSnapshot? in
                let process = Process(); let output = Pipe()
                process.executableURL = executable; process.arguments = ["--permission-status"]
                process.standardOutput = output; process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
                    guard process.terminationStatus == 0, let flags = try JSONSerialization.jsonObject(with: data) as? [String: Bool],
                          let mic = flags["microphone"], let ax = flags["accessibility"], let input = flags["inputMonitoring"] else { return nil }
                    return PermissionSnapshot(microphone: mic, accessibility: ax, input: input)
                } catch { return nil }
            }.value
            refreshing = false
            guard let snapshot else { return }
            let currentAX = AXIsProcessTrusted()
            let restartRequired = snapshot.accessibility && !currentAX
            // Use every fresh result, including Accessibility. The existing process may cache a denial.
            microphone = snapshot.microphone
            accessibility = snapshot.accessibility; inputMonitoring = snapshot.input
            needsRestart = restartRequired
            // Also retry a stopped service after sleep or an explicit recheck, even if grants did not change.
            onChange?()
        }
    }
    func requestMicrophone() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        refresh(); return granted
    }
    func requestAccessibility() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        refresh()
    }
    func requestInput() {
        _ = CGRequestListenEventAccess()
        // Register a read-only tap independently of Accessibility. Never consume keys here.
        if let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue), callback: { _, _, event, _ in Unmanaged.passUnretained(event) }, userInfo: nil) {
            CFMachPortInvalidate(tap)
        }
        refresh()
    }
    func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_" + pane) { NSWorkspace.shared.open(url) }
    }
}
@MainActor final class MicrophoneRecorder: AudioCapture {
    private var recorder: AVAudioRecorder?
    private var file: URL?
    private var token = UUID()
    private var peak: Float = -160
    static var directory: URL { FileManager.default.temporaryDirectory.appendingPathComponent("in.vardaan.flow-audio", isDirectory: true) }
    static func cleanupAbandoned() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        for url in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where ["m4a", "wav"].contains(url.pathExtension) { try fm.removeItem(at: url) }
    }
    func start() async throws {
        cancel(); let session = UUID(); token = session
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            try Task.checkCancellation(); guard token == session else { throw CancellationError() }
            guard granted else { throw FlowError.microphone }
        } else if status != .authorized { throw FlowError.microphone }
        try Task.checkCancellation()
        let url = Self.directory.appendingPathComponent(UUID().uuidString + ".wav")
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            file = url
            // PCM avoids AAC encoder initialization failures on otherwise working inputs.
            // Three minutes of 16 kHz mono, 16-bit audio stays below the upload limit.
            let recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false])
            recorder.isMeteringEnabled = true; peak = -160
            guard recorder.prepareToRecord(), recorder.record(forDuration: 181) else { throw FlowError.recording }
            self.recorder = recorder
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            let underlying = error as NSError
            NSLog("Flow: recording startup failed (%@, %ld)", underlying.domain, underlying.code)
            cancel(); throw FlowError.recording
        }
    }
    var elapsed: TimeInterval { recorder?.currentTime ?? 0 }
    var level: Double {
        guard let recorder else { return 0 }
        recorder.updateMeters(); peak = max(peak, recorder.peakPower(forChannel: 0))
        return min(1, max(0, Double(pow(10, recorder.averagePower(forChannel: 0) / 30))))
    }
    func stop() throws -> URL {
        guard let recorder, let file else { throw FlowError.recording }
        let duration = recorder.currentTime
        recorder.updateMeters(); peak = max(peak, recorder.peakPower(forChannel: 0))
        recorder.stop(); self.recorder = nil
        guard duration >= 0.5 else { cancel(); throw FlowError.tooShort }
        guard peak > -55 else { cancel(); throw FlowError.silent }
        self.file = nil
        return file
    }
    func cancel() {
        token = UUID(); recorder?.stop(); recorder = nil
        if let file {
            do { try FileManager.default.removeItem(at: file) }
            catch { if FileManager.default.fileExists(atPath: file.path) { NSLog("Flow: temporary recording cleanup failed") } }
        }
        file = nil
    }
}
@MainActor final class LoginService {
    var enabled: Bool { SMAppService.mainApp.status == .enabled }
    var status: String {
        switch SMAppService.mainApp.status {
        case .enabled: "Enabled"
        case .requiresApproval: "Waiting for approval in System Settings"
        case .notRegistered: "Off"
        case .notFound: "Not registered"
        @unknown default: "Unavailable"
        }
    }
    func set(_ enabled: Bool) throws {
        guard LoginPolicy.needsChange(enabled: enabled, currentlyEnabled: self.enabled) || (!enabled && SMAppService.mainApp.status == .requiresApproval) else { return }
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}
