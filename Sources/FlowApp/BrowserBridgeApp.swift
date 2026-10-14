import AppKit
import SwiftUI
import Observation
import FlowCore
import ServiceManagement

@MainActor @Observable final class BrowserBridgeModel {
    let browser: ChatGPTBrowser
    let permissions = Permissions()
    let shortcuts = ShortcutService()
    let session: BrowserDictationSession
    let updater = MacUpdater()
    var launchAtLogin = false
    var history: [DictationResult] = []
    var notice = ""
    private(set) var shortcutPresses = 0
    private let store: HistoryStore
    let isDesignPreview: Bool
    private var historyReady = false
    @ObservationIgnored private var statePolling: Task<Void, Never>?
    init(enableShortcut: Bool = true, designPreview: Bool = false) {
        isDesignPreview = designPreview
        browser = ChatGPTBrowser(fixtureHTML: designPreview ? "<html><body>Isolated design fixture</body></html>" : nil)
        session = BrowserDictationSession(browser: browser, insertion: InsertionService())
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Flow", isDirectory: true)
        store = HistoryStore(url: support.appendingPathComponent("browser-history-v1.json"))
        session.saveResult = { [weak self] result in
            guard let self, historyReady else { throw FlowError.storage }
            let updated = Array(([result] + history).prefix(100))
            try await store.save(updated)
            history = updated
        }
        if designPreview {
            history = [
                DictationResult(raw: "आज के लिए तीन काम हैं:\n1. Send the project proposal.\n2. Grocery shopping कर लेना.\n3. शाम को meeting notes review करना.", final: "आज के लिए तीन काम हैं:\n1. Send the project proposal.\n2. Grocery shopping कर लेना.\n3. शाम को meeting notes review करना.", mode: .verbatim),
                DictationResult(raw: "The frontend connects to the backend through an API. Store the response in the database, then update the interface.", final: "The frontend connects to the backend through an API. Store the response in the database, then update the interface.", mode: .verbatim)
            ]
            historyReady = true
            return
        }
        Task {
            do { history = try await store.load(); historyReady = true }
            catch { notice = "Browser history could not be read. Recording is disabled to protect existing history." }
        }
        if enableShortcut {
            shortcuts.onPress = { [weak self] in
                guard let self else { return }
                shortcutPresses += 1; toggle()
            }
            shortcuts.onFailure = { [weak self] in self?.notice = "Keyboard monitoring was interrupted. Recheck permissions." }
            permissions.onChange = { [weak self] in self?.configureShortcut() }
        }
        permissions.refresh()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        browser.restoreConnection()
        statePolling = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
                guard let self else { return }
                if session.state == .recording, await browser.finishedInPage(), session.state == .recording { session.finish() }
            }
        }
    }
    func configureShortcut() {
        guard permissions.accessibility, permissions.inputMonitoring, !permissions.needsRestart else { shortcuts.stop(); return }
        guard !shortcuts.isRunning else { return }
        do { try shortcuts.start(.fnSpace) }
        catch { notice = error.localizedDescription }
    }
    func toggle(localPreview: Bool? = nil) {
        guard !isDesignPreview else { return }
        guard historyReady else { notice = "Wait for local history to load, or resolve its storage error."; return }
        let inside = localPreview ?? (NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier)
        session.toggle(localPreview: inside)
    }
    func stopPolling() { statePolling?.cancel(); statePolling = nil; browser.shutdown() }
    func setLaunchAtLogin(_ enabled: Bool) {
        guard !isDesignPreview else { launchAtLogin = enabled; return }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled && !launchAtLogin { notice = "Allow FlowGpt in System Settings → General → Login Items." }
        } catch { notice = "Couldn’t change launch at login. Check System Settings → General → Login Items." }
    }
    func refreshLaunchAtLogin() { if !isDesignPreview { launchAtLogin = SMAppService.mainApp.status == .enabled } }
    func writeIntegrationReport() {
        guard CommandLine.arguments.contains("--bridge-integration-check") else { return }
        let report: [String: Any] = ["state": session.state.rawValue, "shortcutPresses": shortcutPresses,
            "shortcutRunning": shortcuts.isRunning, "accessibility": permissions.accessibility,
            "inputMonitoring": permissions.inputMonitoring, "microphone": permissions.microphone,
            "connected": browser.connected, "browserWindowHidden": !browser.connectionWindowVisible,
            "localPreview": session.localPreview, "historyCount": history.count, "message": session.message]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: "/tmp/flowgpt-integration-check.json"), options: .atomic)
        }
    }
}

private final class BridgeHUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
private struct BridgeHUD: View {
    let session: BrowserDictationSession
    let browser: ChatGPTBrowser
    var body: some View {
        FlowGptRecordingStrip(state: session.state, audioLevel: browser.audioLevel, finish: { session.finish() })
    }
}

@MainActor final class BrowserBridgeDelegate: NSObject, NSApplicationDelegate {
    private var model: BrowserBridgeModel!
    private var settings: NSWindow!
    private var panel: NSPanel!
    private var status: NSStatusItem!
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let checkingWindows = CommandLine.arguments.contains("--bridge-window-check")
        model = BrowserBridgeModel(enableShortcut: !checkingWindows && !CommandLine.arguments.contains("--bridge-no-shortcut"), designPreview: checkingWindows)
        settings = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 640), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        settings.title = "FlowGpt"; settings.isReleasedWhenClosed = false
        settings.contentView = NSHostingView(rootView: BrowserBridgeView(model: model)); settings.center()
        settings.minSize = NSSize(width: 760, height: 580)
        settings.toolbarStyle = .unified
        panel = BridgeHUDPanel(contentRect: NSRect(x: 0, y: 0, width: 116, height: 44), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.level = .floating; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: BridgeHUD(session: model.session, browser: model.browser))
        model.session.onState = { [weak self] state in
            guard let self else { return }
            model.writeIntegrationReport()
            if state.busy {
                let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
                if let frame = screen?.visibleFrame { panel.setFrameOrigin(NSPoint(x: frame.midX - 58, y: frame.minY + 2)) }
                panel.orderFrontRegardless()
            } else {
                panel.orderOut(nil)
            }
            // Completion must never steal the destination's focus or reopen a
            // window the user closed. Errors/recovery remain available here.
            status?.button?.toolTip = "FlowGpt · " + model.session.message
        }
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "FlowGpt")
        let menu = NSMenu()
        let connection = NSMenuItem(title: "Connecting to ChatGPT…", action: nil, keyEquivalent: "")
        connection.isEnabled = false; menu.addItem(connection); menu.addItem(.separator())
        for (title, action) in [("Start / finish dictation", #selector(toggle)), ("Connect ChatGPT", #selector(connect)), ("History and settings", #selector(showSettings)), ("Quit FlowGpt", #selector(quit))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        status.menu = menu
        menu.delegate = self
        let main = NSMenu(), appItem = NSMenuItem(), appMenu = NSMenu(title: "FlowGpt")
        let settingsItem = NSMenuItem(title: "History and settings", action: #selector(showSettings), keyEquivalent: ","); settingsItem.target = self
        appMenu.addItem(settingsItem)
        let quitItem = NSMenuItem(title: "Quit FlowGpt", action: #selector(quit), keyEquivalent: "q"); quitItem.target = self
        appMenu.addItem(quitItem); appItem.submenu = appMenu; main.addItem(appItem)
        let editItem = NSMenuItem(), edit = NSMenu(title: "Edit")
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] { edit.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key)) }
        editItem.submenu = edit; main.addItem(editItem); NSApp.mainMenu = main
        let loginLaunch = NSAppleEventManager.shared().currentAppleEvent?.eventID == AEEventID(kAEOpenApplication)
            && NSAppleEventManager.shared().currentAppleEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
        if !CommandLine.arguments.contains("--background") && !loginLaunch { showSettings() }
        if checkingWindows { checkWindowLifecycle() }
    }
    private func checkWindowLifecycle() {
        settings.close()
        var checks: [String: Bool] = ["closedSettingsRemainResident": !settings.isVisible,
            "menuBarWithoutDock": NSApp.activationPolicy() == .accessory,
            "nonactivatingStrip": !panel.canBecomeKey && !panel.canBecomeMain]
        model.session.onState?(.starting)
        checks["stripVisibleDuringStartup"] = panel.isVisible
        checks["compactStrip"] = panel.frame.size == NSSize(width: 116, height: 44)
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        checks["stripAtUsableBottomEdge"] = screen.map { abs(panel.frame.minY - $0.visibleFrame.minY - 2) < 0.5 } ?? false
        for state: SessionState in [.success, .attempted, .error, .cancelled] {
            model.session.onState?(state)
            checks["noReopenAfter\(state.rawValue)"] = !settings.isVisible && !panel.isVisible
        }
        let report: [String: Any] = ["type": "Native window lifecycle fixture; no microphone, account or permissions changed", "checks": checks, "passed": checks.values.allSatisfy { $0 }]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: URL(fileURLWithPath: "/tmp/flowgpt-window-check.json"), options: .atomic) }
        NSApp.terminate(nil)
    }
    @objc private func showSettings() { settings.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc private func toggle() { model.toggle() }
    @objc private func connect() { model.browser.show() }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationDidBecomeActive(_ notification: Notification) { model?.permissions.refresh(); model?.refreshLaunchAtLogin() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.stopPolling()
        model.shortcuts.stop()
        Task { await model.session.shutdown(); await InsertionService.waitForPendingPaste(); NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}

extension BrowserBridgeDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        menu.items.first?.title = model.session.state.busy ? model.session.message : (model.session.state == .idle ? model.browser.connectionMessage : model.session.message)
    }
}
