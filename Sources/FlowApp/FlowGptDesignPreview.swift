import AppKit
import SwiftUI
import FlowCore
import Observation

@MainActor @Observable private final class FlowGptVisualFixture {
    var stripState: SessionState?
}

private struct FlowGptPreviewSurface: View {
    let model: BrowserBridgeModel
    let fixture: FlowGptVisualFixture
    var body: some View {
        BrowserBridgeView(model: model).overlay(alignment: .bottom) {
            if let state = fixture.stripState {
                VStack(spacing: 0) {
                    Text("Visual preview · microphone off").font(.caption2).foregroundStyle(.secondary)
                    FlowGptRecordingStrip(state: state, audioLevel: 0.7, finish: { fixture.stripState = .transcribing })
                }.padding(.bottom, 14)
            }
        }
    }
}

/// Isolated visual fixtures: no audio, sign-in, history reads or shortcut tap.
@MainActor final class FlowGptDesignPreviewDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let fixture = FlowGptVisualFixture()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let model = BrowserBridgeModel(enableShortcut: false, designPreview: true)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 700), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "FlowGpt · Design preview"
        window.minSize = NSSize(width: 760, height: 580)
        window.toolbarStyle = .unified
        window.contentView = NSHostingView(rootView: FlowGptPreviewSurface(model: model, fixture: fixture))
        window.isReleasedWhenClosed = false; window.center()
        let main = NSMenu(), appItem = NSMenuItem(), appMenu = NSMenu()
        let quit = NSMenuItem(title: "Quit design preview", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(quit); appItem.submenu = appMenu; main.addItem(appItem)
        let item = NSMenuItem(), menu = NSMenu(title: "Preview")
        for (name, action) in [
            ("Recording strip", #selector(recording)), ("Processing strip", #selector(processing)),
            ("Hide strip", #selector(hideStrip)), ("Compact window", #selector(compact)),
            ("Large window", #selector(large)), ("Dark appearance", #selector(dark)), ("Light appearance", #selector(light))
        ] {
            let entry = NSMenuItem(title: name, action: action, keyEquivalent: ""); entry.target = self; menu.addItem(entry)
        }
        item.submenu = menu; main.addItem(item); NSApp.mainMenu = main
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    private func showStrip(_ state: SessionState) {
        fixture.stripState = state
    }
    @objc private func recording() { showStrip(.recording) }
    @objc private func processing() { showStrip(.transcribing) }
    @objc private func hideStrip() { fixture.stripState = nil }
    @objc private func compact() { window.setContentSize(NSSize(width: 760, height: 580)) }
    @objc private func large() { window.setContentSize(NSSize(width: 1060, height: 780)) }
    @objc private func dark() { window.appearance = NSAppearance(named: .darkAqua) }
    @objc private func light() { window.appearance = NSAppearance(named: .aqua) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
