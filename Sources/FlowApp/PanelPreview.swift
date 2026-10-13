// Isolated UI diagnostic. Uses the production session/panel with synthetic
// adapters; it never records audio, requests privacy grants or calls an API.
import AppKit
import SwiftUI
import Observation
import FlowCore

@MainActor private final class PreviewAudio: AudioCapture {
    private var began = Date()
    private let url = FileManager.default.temporaryDirectory.appendingPathComponent("Flow-panel-demo-" + UUID().uuidString + ".m4a")
    var level: Double { 0.35 + 0.3 * abs(sin(elapsed * 4)) }
    var elapsed: TimeInterval { Date().timeIntervalSince(began) }
    func start() async throws { began = Date(); try Data([1]).write(to: url) }
    func stop() throws -> URL { url }
    func cancel() { try? FileManager.default.removeItem(at: url) }
}
private actor PreviewPipeline: TextPipeline {
    func transcribe(audio: URL, key: String, preferences: Preferences) async throws -> String {
        try await Task.sleep(for: .seconds(3)); return "Demo text. नमस्ते।"
    }
    func clean(text: String, key: String, preferences: Preferences) async throws -> String {
        try await Task.sleep(for: .seconds(2)); return text
    }
}
@MainActor @Observable private final class PreviewInsertion: TextInsertion {
    var text = ""
    func captureTarget() { text = "" }
    func reset() {}
    func insert(_ text: String, preserveClipboard: Bool) async throws -> InsertionOutcome {
        try await Task.sleep(for: .seconds(2)); self.text = text; return .confirmed
    }
}
@MainActor @Observable private final class PreviewStatus { var visible = false }
@MainActor final class PanelPreviewDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var panel: PanelController?
    private var timer: Timer?
    private let insertion = PreviewInsertion()
    private let status = PreviewStatus()
    private var session: SessionController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let session = SessionController(audio: PreviewAudio(), pipeline: PreviewPipeline(), insertion: insertion)
        self.session = session
        let panel = PanelController(session: session, enabled: { true }, openResult: {})
        self.panel = panel
        session.onState = { [weak self] state in
            panel.update(state)
            self?.status.visible = panel.isVisible
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 370), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Flow Glass Preview"; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PreviewControls(session: session, insertion: insertion, status: status))
        window.center(); window.makeKeyAndOrderFront(nil); self.window = window
        NSApp.activate(ignoringOtherApps: true)
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            MainActor.assumeIsolated { session.tick() }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate(); session?.cancel() }
}
private struct PreviewControls: View {
    var session: SessionController
    var insertion: PreviewInsertion
    var status: PreviewStatus
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Production panel · synthetic session").font(.headline)
            Text("No microphone, API or permission changes.").foregroundStyle(.secondary)
            HStack {
                Button("Start demonstration") { session.begin(key: "demo", preferences: Preferences()) }.disabled(session.state.busy)
                Button("Finish demonstration") { session.stop() }.disabled(session.state != .recording)
                Button("Cancel") { session.cancel() }.disabled(!session.state.busy)
            }
            Text("State: \(session.state.rawValue) · popup \(status.visible ? "visible" : "hidden")")
            Text("Delivered demo: \(insertion.text)")
            ZStack {
                LinearGradient(colors: [.indigo.opacity(0.5), .teal.opacity(0.4), .gray.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                if status.visible { RecordingPanelView(session: session, openResult: {}) }
            }.frame(height: 84).clipShape(RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel("Same production view, shown here for screenshot inspection")
        }.padding(24).frame(width: 520, height: 370, alignment: .leading)
    }
}
