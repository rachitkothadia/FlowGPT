import AppKit
import SwiftUI
import FlowCore
import AVFoundation
import Darwin

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var model: AppModel!
    private var panel: PanelController!
    private var status: NSStatusItem!
    private var settings: NSWindow?
    private var timer: Timer?
        func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        model = AppModel(); model.applyAppearance(); panel = PanelController(model: model)
        model.showSettings = { [weak self] in self?.openSettings() }
        model.panelChanged = { [weak self] state in self?.panel.update(state) }
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Flow Dictation")
        status.button?.toolTip = "Flow · " + model.preferences.shortcut.label
        status.menu = NSMenu(); status.menu?.delegate = self
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.model.tick() } }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wake), name: NSWorkspace.didWakeNotification, object: nil)
        if !UserDefaults.standard.bool(forKey: "onboardingShown") || !model.preferences.backgroundLaunch || UserDefaults.standard.bool(forKey: "reopenSettingsAfterRestart") {
            openSettings(); UserDefaults.standard.set(true, forKey: "onboardingShown")
            UserDefaults.standard.set(false, forKey: "reopenSettingsAfterRestart")
        }
        if CommandLine.arguments.contains("--recording-ui-check") {
            // Exercise the real Settings -> AppModel -> microphone -> panel path; never upload audio.
            openSettings(); NSApp.activate(ignoringOtherApps: true)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                model.preferences.continuous = false
                model.preferences.showPanel = true
                model.begin()
                try? await Task.sleep(for: .seconds(4))
                let passed = model.session.state == .recording && model.session.isLocalPreview && model.session.elapsed >= 2 && panel.isVisible
                let report: [String: Any] = ["passed": passed, "state": model.session.state.rawValue,
                    "settingsPreview": model.session.isLocalPreview, "elapsedSeconds": model.session.elapsed,
                    "panelVisible": panel.isVisible, "message": model.session.message]
                if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                    try? data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("flow-recording-ui-check.json"), options: .atomic)
                }
                model.session.cancel(); NSApp.terminate(nil)
            }
        }
    }
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu(title: "Flow")
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","); settingsItem.target = self
        let quitItem = NSMenuItem(title: "Quit Flow", action: #selector(quit), keyEquivalent: "q"); quitItem.target = self
        appMenu.addItem(settingsItem); appMenu.addItem(.separator()); appMenu.addItem(quitItem); appItem.submenu = appMenu; main.addItem(appItem)
        let editItem = NSMenuItem(); let edit = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        editItem.submenu = edit; main.addItem(editItem)
        let windowItem = NSMenuItem(); let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowItem.submenu = windowMenu; main.addItem(windowItem); NSApp.mainMenu = main
    }
    func applicationDidBecomeActive(_ notification: Notification) { model?.refreshPermissions() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        timer?.invalidate()
        Task { await model.prepareToTerminate(); NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate(); model.shutdown() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openSettings(); return true }
    @objc private func willSleep() { if model.session.state.busy { model.session.cancel() }; model.shortcuts.stop() }
    @objc private func wake() { model.recheckPermissions() }
    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        add(menu, model.session.state == .recording ? "Finish Dictation" : "Start Dictation", #selector(toggle), enabled: !model.session.state.busy || model.session.state == .recording)
        add(menu, "Cancel Dictation", #selector(cancel), enabled: model.session.state.busy)
        menu.addItem(.separator())
        add(menu, "Copy Last Final Text", #selector(copyFinal), enabled: !model.session.finalText.isEmpty)
        add(menu, "Copy Last Transcript", #selector(copyRaw), enabled: !model.session.rawText.isEmpty)
        add(menu, "Retry Insertion", #selector(retry), enabled: model.session.canRetryInsertion && !model.session.state.busy)
        add(menu, "Show Last Result…", #selector(result))
        menu.addItem(.separator())
        add(menu, "Settings…", #selector(openSettings))
        add(menu, "Recheck Permissions", #selector(recheck))
        menu.addItem(.separator())
        add(menu, "Quit Flow", #selector(quit))
    }
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, enabled: Bool = true) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; item.isEnabled = enabled; menu.addItem(item)
    }
    @objc private func toggle() { model.toggle() }
    @objc private func cancel() { model.session.cancel() }
    @objc private func copyFinal() { model.copy(model.session.finalText) }
    @objc private func copyRaw() { model.copy(model.session.rawText) }
    @objc private func retry() { model.session.retryInsertion() }
    @objc private func result() { openSettings(); model.resultRevision += 1 }
    @objc private func recheck() { model.recheckPermissions() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func openSettings() {
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 650), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Flow Settings"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: model)); window.center()
            settings = window
        }
        model.revision += 1
        settings?.makeKeyAndOrderFront(nil); NSApp.activate()
    }
}
@main struct FlowApplication {
    static func audioCheck() {
        do {
            for hours in [1, 2, 4, 10] { print(try ContinuousAudioDiagnostics.verify(hours: hours)) }
            exit(0)
        } catch { print("PCM continuity check failed: \(error.localizedDescription)"); exit(1) }
    }
    @MainActor static func main() {
        if CommandLine.arguments.contains("--connection-recovery-check") {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            BrowserBridgeChecks.checkRecovery()
            app.run(); return
        }
        if CommandLine.arguments.contains("--native-capture-timing") {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            BrowserBridgeChecks.checkNativeTiming()
            app.run(); return
        }
        if CommandLine.arguments.contains("--bridge-window-check") {
            let app = NSApplication.shared
            let delegate = BrowserBridgeDelegate()
            app.delegate = delegate
            withExtendedLifetime(delegate) { app.run() }
            return
        }
        if CommandLine.arguments.contains("--design-preview") {
            let app = NSApplication.shared
            let delegate = FlowGptDesignPreviewDelegate()
            app.delegate = delegate
            withExtendedLifetime(delegate) { app.run() }
            return
        }
        if CommandLine.arguments.contains("--browser-driver-check") {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            BrowserBridgeChecks.run()
            app.run()
            return
        }
        if CommandLine.arguments.contains("--bridge-recording-check") {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            BrowserBridgeChecks.checkHiddenRecording()
            app.run()
            return
        }
        if Bundle.main.object(forInfoDictionaryKey: "FlowPanelPreview") as? Bool == true {
            let app = NSApplication.shared
            let delegate = PanelPreviewDelegate()
            app.delegate = delegate
            withExtendedLifetime(delegate) { app.run() }
            return
        }
        if CommandLine.arguments.contains("--clipboard-check") {
            // Named test board never touches the user's clipboard or privacy grants.
            let board = NSPasteboard(name: .init("Flow-QA-" + UUID().uuidString))
            defer { board.releaseGlobally() }
            let clipboard = NativeClipboard(board: board)
            do {
                let item = NSPasteboardItem()
                item.setString("original", forType: .string)
                item.setData(Data("{\\rtf1 original}".utf8), forType: .rtf)
                let second = NSPasteboardItem()
                second.setData(Data([3, 4, 5]), forType: .init("com.flow.test-binary"))
                board.writeObjects([item, second])
                let original = try clipboard.snapshot()
                let lease = try ClipboardLease(clipboard, text: "नमस्ते 🎤\nC++ Swift")
                lease.restore()
                guard try clipboard.snapshot() == original else { print("Multiple-item restoration failed"); throw FlowError.insertion }
                let next = try ClipboardLease(clipboard, text: "temporary")
                _ = try clipboard.write("new user copy")
                next.restore()
                guard board.string(forType: .string) == "new user copy" else { print("Concurrent copy failed"); throw FlowError.insertion }
                board.clearContents()
                let empty = try ClipboardLease(clipboard, text: "temporary")
                empty.restore()
                guard board.pasteboardItems?.isEmpty != false else { print("Empty restoration failed"); throw FlowError.insertion }
                print("Native clipboard: multiple items, all formats, concurrent copy and empty restoration passed")
                exit(0)
            } catch { print("Native clipboard check failed: \(error.localizedDescription)"); exit(1) }
        }
        if CommandLine.arguments.contains("--audio-continuity-check") { audioCheck(); return }
        if CommandLine.arguments.contains("--insertion-check") {
            // Developer diagnostic: invoke the same production insertion path in a
            // disposable editor. Clipboard data is compared in memory, never logged.
            Task { @MainActor in
                do {
                    try await Task.sleep(for: .seconds(8))
                    let insertion = InsertionService()
                    insertion.useAccessibility = !CommandLine.arguments.contains("--paste-only")
                    insertion.captureTarget()
                    print(insertion.diagnosticTarget())
                    let clipboard = NativeClipboard()
                    let before = try clipboard.snapshot()
                    var text = "Flow 3.0.1: नमस्ते। नमस्कार। বাংলা தமிழ் తెలుగు ಕನ್ನಡ മലയാളം اردو 🎤\nRust C++ C# Swift SQL"
                    if CommandLine.arguments.contains("--single-line") { text = "Flow 3.0.1: नमस्ते। नमस्कार। 🎤 Rust C++ C# Swift SQL" }
                    if let index = CommandLine.arguments.firstIndex(of: "--insertion-text-file"), index + 1 < CommandLine.arguments.count {
                        text = try String(contentsOfFile: CommandLine.arguments[index + 1], encoding: .utf8)
                    }
                    let outcome = try await insertion.insert(text, preserveClipboard: true)
                    let restored = try clipboard.snapshot() == before
                    print("Native insertion: \(outcome) · all clipboard formats restored: \(restored)")
                    exit(outcome == .confirmed && restored ? 0 : 1)
                } catch { print("Native insertion check: \(error.localizedDescription)"); exit(1) }
            }
            RunLoop.main.run(); return
        }
        if CommandLine.arguments.contains("--credential-check") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Flow-credential-check-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("api-key.txt")
            let model = AppModel(keyStoreURL: url, enableServices: false)
            model.saveKey("test-only")
            let reopened = AppModel(keyStoreURL: url, enableServices: false)
            let restored = reopened.apiKey == "test-only"
            reopened.speechProbe = ModelProbeResult(statusCode: 200, message: "previous")
            reopened.textProbe = ModelProbeResult(statusCode: 200, message: "previous")
            // Even with a saved credential, an explicitly empty field must never start requests.
            reopened.testConnection(enteredKey: "")
            let emptyRejected = !reopened.testingConnection && reopened.speechProbe == nil && reopened.textProbe == nil
            reopened.deleteKey()
            let removed = (try? APIKeyStore(url: url).load()) == "" && reopened.apiKey.isEmpty
            print("Credential check: restored=\(restored), emptyFieldRejected=\(emptyRejected), removed=\(removed)")
            exit(restored && emptyRejected && removed ? 0 : 1)
        }
        if CommandLine.arguments.contains("--format-transcript") {
            let input = FileHandle.standardInput.readDataToEndOfFile()
            guard let text = String(data: input, encoding: .utf8), !text.isEmpty else { exit(1) }
            Task { @MainActor in
                do {
                    let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Flow/api-key.txt")
                    let key = try APIKeyStore(url: url).load()
                    let result = try await GroqClient().clean(text: text, key: key, preferences: Preferences())
                    print(result); exit(0)
                } catch { print("Formatting check failed: \(error.localizedDescription)"); exit(1) }
            }
            RunLoop.main.run(); return
        }
        if CommandLine.arguments.contains("--microphone-check") {
            // Explicit local diagnostic: no upload or transcript, and always delete audio.
            Task { @MainActor in
                let recorder = MicrophoneRecorder()
                do {
                    try await recorder.start()
                    try await Task.sleep(for: .seconds(1))
                    let elapsed = recorder.elapsed
                    recorder.cancel()
                    print("Microphone recording check: \(elapsed >= 0.5 ? "PASS" : "FAIL") (\(elapsed) seconds)")
                    exit(elapsed >= 0.5 ? 0 : 1)
                } catch {
                    recorder.cancel()
                    print("Microphone recording check: FAIL (\(error.localizedDescription))")
                    exit(1)
                }
            }
            RunLoop.main.run()
            return
        }
        if CommandLine.arguments.contains("--continuous-microphone-check") {
            Task { @MainActor in
                let recorder = ContinuousRecorder()
                do {
                    try await recorder.start()
                    try await Task.sleep(for: .seconds(3))
                    let elapsed = recorder.elapsed
                    let segments = try recorder.finishSegments()
                    var frames: Int64 = 0
                    for url in segments { frames += try AVAudioFile(forReading: url).length }
                    if let directory = recorder.recordingDirectory { try? FileManager.default.removeItem(at: directory) }
                    let passed = elapsed >= 1 && frames >= 16000
                    print("Continuous microphone hardware: \(passed ? "PASS" : "FAIL") · \(elapsed) seconds · \(frames) frames")
                    exit(passed ? 0 : 1)
                } catch {
                    recorder.cancel()
                    if let directory = recorder.recordingDirectory { try? FileManager.default.removeItem(at: directory) }
                    print("Continuous microphone hardware: FAIL · \(error.localizedDescription)"); exit(1)
                }
            }
            RunLoop.main.run(); return
        }
        if CommandLine.arguments.contains("--permission-status") {
            let status = ["microphone": AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
                          "accessibility": AXIsProcessTrusted(), "inputMonitoring": CGPreflightListenEventAccess()]
            if let data = try? JSONSerialization.data(withJSONObject: status), let string = String(data: data, encoding: .utf8) { print(string) }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--relaunch-after"), CommandLine.arguments.count > index + 1,
           let parent = Int32(CommandLine.arguments[index + 1]), let bundle = Bundle.main.bundleURL as URL?, bundle.pathExtension == "app" {
            for _ in 0..<100 { if kill(parent, 0) != 0 { break }; usleep(100_000) }
            guard kill(parent, 0) != 0 else { return }
            let launcher = Process(); launcher.executableURL = URL(fileURLWithPath: "/usr/bin/open"); launcher.arguments = ["-n", bundle.path]
            try? launcher.run(); launcher.waitUntilExit(); return
        }
        if CommandLine.arguments.contains("--self-check") {
            let report: [String: Any] = ["bundle": Bundle.main.bundleIdentifier ?? "unbundled", "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "missing", "guidePackaged": Bundle.main.url(forResource: "UserGuide", withExtension: "md") != nil, "microphoneUsagePresent": Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil, "architecture": "arm64"]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), let string = String(data: data, encoding: .utf8) { print(string) }
            return
        }
        if NSRunningApplication.runningApplications(withBundleIdentifier: "in.vardaan.flow").contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) { return }
        if Bundle.main.object(forInfoDictionaryKey: "FlowBrowserBridge") as? Bool == true || CommandLine.arguments.contains("--browser-bridge") {
            let app = NSApplication.shared
            let delegate = BrowserBridgeDelegate()
            app.delegate = delegate
            withExtendedLifetime(delegate) { app.run() }
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
