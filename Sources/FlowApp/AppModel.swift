import AppKit
import Observation
import FlowCore

@MainActor @Observable final class AppModel {
    var preferences = Preferences()
    var history: [DictationResult] = []
    var notice = ""
    var connectionStatus = ""
    private(set) var apiKey = ""
    var hasKey: Bool { !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var testingConnection = false
    var speechProbe: ModelProbeResult?
    var textProbe: ModelProbeResult?
    private var lastPermissionCheck = Date.distantPast
    private var connectionToken = UUID()
    var revision = 0
    var resultRevision = 0
    let permissions = Permissions()
    let login = LoginService()
    let shortcuts = ShortcutService()
    let session: SessionController
    private let pipeline: GroqClient
    private let historyStore: HistoryStore
    private let keyStore: APIKeyStore
    private var historyWork: Task<Void, Never>?
    private var connectionWork: Task<Void, Never>?
    var showSettings: (() -> Void)?
    var panelChanged: ((SessionState) -> Void)?
    init(keyStoreURL: URL? = nil, enableServices: Bool = true) {
        pipeline = GroqClient()
        session = SessionController(audio: AdaptiveRecorder(), pipeline: pipeline, insertion: InsertionService())
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Flow", isDirectory: true)
        historyStore = HistoryStore(url: support.appendingPathComponent("history-v1.json"))
        keyStore = APIKeyStore(url: keyStoreURL ?? support.appendingPathComponent("api-key.txt"))
        do { preferences = try PreferenceStore.load(from: .standard) } catch { notice = FlowError.storage.localizedDescription }
        if enableServices, !UserDefaults.standard.bool(forKey: "flow4MixedLanguageDefault") {
            preferences.language = ""
            do {
                try PreferenceStore.save(preferences, to: .standard)
                UserDefaults.standard.set(true, forKey: "flow4MixedLanguageDefault")
            } catch { notice = FlowError.storage.localizedDescription }
        }
        do { apiKey = try keyStore.load() } catch { notice = "Your saved API key could not be read. Paste it again in Connection." }
        do { try MicrophoneRecorder.cleanupAbandoned() } catch { notice = "Temporary recordings could not be cleaned up. Check disk permissions." }
        if enableServices, preferences.historyEnabled {
            Task { do { let entries = try await historyStore.load(); if preferences.historyEnabled { history = entries } } catch { notice = FlowError.storage.localizedDescription } }
        }
        session.onResult = { [weak self] result in self?.remember(result) }
        session.onState = { [weak self] state in
            guard let self else { return }
            panelChanged?(state)
            if state == .success, session.isLocalPreview { resultRevision += 1; showSettings?() }
        }
        shortcuts.onPress = { [weak self] in
            guard let self else { return }
            if preferences.pushToTalk { begin() } else { toggle() }
        }
        shortcuts.onRelease = { [weak self] in
            guard let self, preferences.pushToTalk else { return }
            if session.state == .starting { session.cancel() } else { session.stop() }
        }
        shortcuts.onFailure = { [weak self] in self?.notice = "Keyboard monitoring was interrupted. Recheck permissions if the shortcut stops responding." }
        permissions.onChange = { [weak self] in
            guard let self else { return }
            revision += 1
            if session.state.busy, !preferences.isContinuous, !session.isLocalPreview, !permissions.accessibility || !permissions.inputMonitoring { session.cancel() }
            if permissions.needsRestart, !session.state.busy, session.finalText.isEmpty, session.rawText.isEmpty {
                let last = UserDefaults.standard.double(forKey: "permissionRestartAt")
                if Date().timeIntervalSince1970 - last > 60 {
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "permissionRestartAt")
                    UserDefaults.standard.set(NSApp.isActive, forKey: "reopenSettingsAfterRestart")
                    restart(); return
                }
                notice = "Accessibility is allowed. Restart Flow once to apply macOS's updated permission."
            }
            configureShortcut()
        }
        if enableServices { permissions.refresh(); configureShortcut() }
    }
    private func credential() -> String {
        (try? APIKeyStore.validated(apiKey)) ?? ""
    }
    func toggle() {
        if session.state == .recording { session.stop(); return }
        begin()
    }
    func begin() {
        guard !session.state.busy else { return }
        let insideFlow = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
        session.begin(key: credential(), preferences: preferences, insertIntoTarget: !insideFlow)
    }
    var recordingFolders: [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: RecordingArchive.root, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.hasDirectoryPath }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    func recoverRecording(_ url: URL) { session.recoverRecording(at: url, key: credential(), preferences: preferences) }
    func openRecordings() {
        try? FileManager.default.createDirectory(at: RecordingArchive.root, withIntermediateDirectories: true)
        NSWorkspace.shared.open(RecordingArchive.root)
    }
    func savePreferences(previous: Preferences) {
        preferences.sanitize()
        do { try PreferenceStore.save(preferences, to: .standard) } catch { notice = FlowError.storage.localizedDescription }
        if previous.shortcut != preferences.shortcut || previous.shortcutEnabled != preferences.shortcutEnabled || previous.pushToTalk != preferences.pushToTalk {
            if session.state == .recording || session.state == .starting { session.cancel() }
            configureShortcut()
        }
        if previous.historyEnabled && !preferences.historyEnabled { clearHistory() }
        applyAppearance()
    }
    func configureShortcut() {
        guard preferences.shortcutEnabled, permissions.accessibility, permissions.inputMonitoring, !permissions.needsRestart else { shortcuts.stop(); return }
        if shortcuts.isRunning, shortcuts.matches(preferences.shortcut) { return }
        do {
            try shortcuts.start(preferences.shortcut)
            if notice == FlowError.shortcut.localizedDescription || notice.hasPrefix("macOS has granted permission") { notice = "" }
        }
        catch { notice = "macOS has granted permission, but the shortcut service is not ready. Use Restart Flow to apply it." }
    }
    func recheckPermissions() { permissions.refresh(); revision += 1 }
    func refreshPermissions() { permissions.refresh() }
    func restart() {
        guard let executable = Bundle.main.executableURL else { return }
        let process = Process(); process.executableURL = executable
        process.arguments = ["--relaunch-after", String(ProcessInfo.processInfo.processIdentifier)]
        do { try process.run(); NSApp.terminate(nil) }
        catch { notice = "Could not reopen Flow. Quit and open it from Applications." }
    }
    func tick() {
        session.tick()
        if Date().timeIntervalSince(lastPermissionCheck) >= 3.0 {
            lastPermissionCheck = Date(); refreshPermissions()
        }
        if session.state == .recording && !(preferences.isContinuous && preferences.audioSource == "Computer audio") && !permissions.microphone { session.cancel(); notice = FlowError.microphone.localizedDescription }
    }
    func applyAppearance() {
        NSApp.appearance = preferences.appearance == "System" ? nil : NSAppearance(named: preferences.appearance == "Dark" ? .darkAqua : .aqua)
    }
    func saveKey(_ value: String) {
        connectionToken = UUID(); connectionWork?.cancel(); testingConnection = false; speechProbe = nil; textProbe = nil
        apiKey = value
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do { try keyStore.delete(); connectionStatus = "Paste an API key to test it" }
            catch { connectionStatus = "Could not remove the saved key. Check disk permissions." }
            return
        }
        do { try keyStore.save(value); connectionStatus = "Saved on this Mac · used for dictation" }
        catch { connectionStatus = "Could not save the key. Check the key and disk permissions." }
    }
    func deleteKey() {
        connectionToken = UUID(); connectionWork?.cancel(); testingConnection = false; speechProbe = nil; textProbe = nil
        saveKey("")
    }
    func testConnection(enteredKey: String = "") {
        guard !testingConnection else { return }
        let entered = enteredKey.trimmingCharacters(in: .whitespacesAndNewlines)
        speechProbe = nil; textProbe = nil
        // Test exactly what is visible in the field. Never fall back to another credential.
        guard let key = try? APIKeyStore.validated(entered) else { connectionStatus = "Paste an API key before testing"; return }
        let token = UUID(); connectionToken = token
        testingConnection = true; speechProbe = nil; textProbe = nil; connectionStatus = "Testing both models…"
        connectionWork = Task {
            defer { if connectionToken == token { testingConnection = false } }
            do {
                guard let url = Bundle.main.url(forResource: "ConnectionSample", withExtension: "m4a") else { throw FlowError.storage }
                let sample = try Data(contentsOf: url)
                let speech = try await pipeline.testSpeech(key: key, sample: sample)
                try Task.checkCancellation(); guard connectionToken == token else { return }; speechProbe = speech
                let text = try await pipeline.testText(key: key)
                try Task.checkCancellation(); guard connectionToken == token else { return }; textProbe = text
                connectionStatus = speech.passed && text.passed ? "Both models returned HTTP 200" : "One or more tests failed. See results below."
            } catch is CancellationError { }
            catch { if connectionToken == token { connectionStatus = (error as? FlowError ?? .network).localizedDescription } }
        }
    }
    func setLogin(_ value: Bool) {
        do { try login.set(value); revision += 1 }
        catch { notice = "Start at Login could not be changed. Check System Settings → General → Login Items." }
    }
    func copy(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        if !NSPasteboard.general.setString(text, forType: .string) { notice = "Could not copy text to the clipboard." }
    }
    private func remember(_ result: DictationResult) {
        guard preferences.historyEnabled else { return }
        history.insert(result, at: 0); history = Array(history.prefix(100)); persistHistory()
    }
    func deleteHistory(_ id: UUID) { history.removeAll { $0.id == id }; persistHistory() }
    func clearHistory() {
        history = []; let previous = historyWork
        historyWork = Task {
            await previous?.value
            do { try await historyStore.clear() } catch { notice = FlowError.storage.localizedDescription }
        }
    }
    private func persistHistory() {
        let entries = history; let previous = historyWork
        historyWork = Task {
            await previous?.value
            do { try await historyStore.save(entries) } catch { notice = FlowError.storage.localizedDescription }
        }
    }
    func exportDiagnostics() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Flow-Diagnostics.txt"; panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let report = """
        Flow \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development")
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Microphone: \(permissions.microphone)
        Accessibility: \(permissions.accessibility)
        Input Monitoring: \(permissions.inputMonitoring)
        Credential configured: \(hasKey)
        Shortcut enabled: \(preferences.shortcutEnabled)
        Session state: \(session.state.rawValue)
        Login item: \(login.status)
        History enabled: \(preferences.historyEnabled)
        Models: \(GroqRequest.speechModel(for: preferences)), \(GroqRequest.textModel)
        No audio, transcripts, clipboard data or credentials included.
        """
        do { try report.write(to: url, atomically: true, encoding: .utf8) } catch { notice = "Could not save the diagnostic report." }
    }
    func prepareToTerminate() async { connectionWork?.cancel(); shortcuts.stop(); await session.shutdown(); await InsertionService.waitForPendingPaste(); await historyWork?.value }
    func shutdown() { connectionWork?.cancel(); shortcuts.stop(); session.cancel() }
}
