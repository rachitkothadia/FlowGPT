import SwiftUI
import AppKit
import FlowCore

private final class DictationPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
@MainActor final class PanelController {
    private let panel: NSPanel
    private let session: SessionController
    private let enabled: () -> Bool
    var isVisible: Bool { panel.isVisible }
    convenience init(model: AppModel) {
        self.init(session: model.session, enabled: { model.preferences.showPanel }, openResult: { model.showSettings?() })
    }
    init(session: SessionController, enabled: @escaping () -> Bool, openResult: @escaping () -> Void) {
        self.session = session; self.enabled = enabled
        panel = DictationPanel(contentRect: NSRect(x: 0, y: 0, width: 176, height: 56), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating; panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.contentView = NSHostingView(rootView: RecordingPanelView(session: session, openResult: openResult))
    }
    func update(_ state: SessionState) {
        guard enabled(), PanelPresentation(state: state) != .hidden else { panel.orderOut(nil); return }
        if !panel.isVisible {
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
            if let frame = screen?.visibleFrame { panel.setFrameOrigin(NSPoint(x: frame.midX - 88, y: frame.minY + 40)) }
            panel.orderFrontRegardless()
        }
        // No success toast or delayed dismissal. Keep session results available
        // through History/menu recovery without keeping the recording UI onscreen.
    }
}
struct RecordingPanelView: View {
    var session: SessionController
    var openResult: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.accessibilityReduceTransparency) private var reducedTransparency
    private var presentation: PanelPresentation { PanelPresentation(state: session.state) }
    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
    private var controls: some View {
        HStack(spacing: 12) {
            Group {
                if presentation == .processing {
                    ProgressView().progressViewStyle(.circular).controlSize(.small)
                        .accessibilityLabel("Processing dictation")
                } else {
                    Button {
                        if presentation == .recording { session.stop() }
                        else { openResult() }
                    } label: {
                        Image(systemName: presentation == .error ? "exclamationmark.circle" : "mic.fill")
                            .font(.system(size: 13, weight: .medium))
                    }.buttonStyle(.plain)
                        .accessibilityLabel(presentation == .recording ? "Finish recording" : "Open result")
                }
            }.frame(width: 18, height: 22)
            HStack(spacing: 2.2) {
                ForEach(0..<23, id: \.self) { index in
                    let variation = 0.3 + 0.7 * abs(sin(Double(index) * 0.8 + (reducedMotion ? 0 : session.elapsed * 4)))
                    let amplitude = presentation == .recording ? min(1, max(0, session.level)) : 0
                    Capsule().fill(.primary.opacity(presentation == .recording ? 0.95 : 0.35))
                        .frame(width: 1.8, height: 2 + 17 * amplitude * variation)
                }
            }.frame(width: 90, height: 22)
                .accessibilityLabel(presentation == .recording ? "Microphone level" : "Processing")
                .accessibilityValue(presentation == .recording ? "\(Int(session.level * 100)) percent" : "")
        }
        .foregroundStyle(presentation == .error ? Color.orange : Color.white)
        .padding(.horizontal, 15).frame(width: 150, height: 36)
    }
    @ViewBuilder private var surface: some View {
        if reducedTransparency {
            controls.background(Color(white: 0.09), in: shape)
        } else if #available(macOS 26.0, *) {
            controls.glassEffect(.regular.interactive(), in: shape)
        } else {
            controls.background(.ultraThinMaterial, in: shape)
        }
    }
    var body: some View {
        surface
            .environment(\.colorScheme, .dark)
            .shadow(color: .black.opacity(0.16), radius: 7, y: 3)
            .frame(width: 176, height: 56)
            .help(session.message).accessibilityElement(children: .contain)
            .accessibilityLabel(presentation == .recording ? "Flow recording" : "Flow " + session.message)
            .contextMenu {
                if session.state == .recording { Button("Finish recording") { session.stop() } }
                if session.state.busy { Button("Cancel") { session.cancel() } }
                if session.canRetryInsertion { Button("Retry insertion") { session.retryInsertion() } }
                Button("Open result", action: openResult)
            }
    }
}
