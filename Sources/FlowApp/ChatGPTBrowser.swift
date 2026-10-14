import AppKit
import WebKit
import AVFoundation
import Observation
import FlowCore

private final class ConnectionWindow: NSWindow {
    var rendersInBackground = true
    override var canBecomeKey: Bool { !rendersInBackground }
    override var canBecomeMain: Bool { !rendersInBackground }
    // Cocoa normally constrains newly ordered windows back onto a display.
    // The connection renderer must be allowed to remain offscreen.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Only the visible composer and labelled dictation controls are accessed.
/// No private endpoints, cookies, tokens, passwords or conversation scraping.
@MainActor @Observable final class ChatGPTBrowser: NSObject, BrowserDictationDriver, WKUIDelegate, WKNavigationDelegate {
    let webView: WKWebView
    private(set) var connected = false
    private(set) var connectionMessage = "Connecting to ChatGPT…"
    private var owned = false
    private var window: ConnectionWindow?
    private var lastError: String?
    private var home = URL(string: "https://chatgpt.com/")!
    private(set) var audioLevel: Double = 0
    private(set) var inputName = "Mac microphone"
    private(set) var captureStartMilliseconds: Double = 0
    private(set) var recorderStartMilliseconds: Double = 0
    private var startupError: String?
    private var recorderReady = false
    private let microphone = NativeBrowserMicrophone()
    var nativeCaptureActive: Bool { microphone.isCapturing }
    var firstFrameMilliseconds: Double? { microphone.firstFrameMilliseconds }
    @ObservationIgnored private var recorderStartup: Task<Void, Never>?
    @ObservationIgnored private var audioPump: Task<Void, Never>?
    @ObservationIgnored private var metering: Task<Void, Never>?
    @ObservationIgnored private var health: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    private var recovery = BrowserConnectionRecovery()
    private var observedDraft = false
    private var navigationStartedAt = ProcessInfo.processInfo.systemUptime
    private let fixtureHTML: String?
    private(set) var recoveryReloads = 0
    @ObservationIgnored private var connectionCheck: Task<Void, Never>?
    init(fixtureHTML: String? = nil) {
        self.fixtureHTML = fixtureHTML
        let config = WKWebViewConfiguration()
        config.websiteDataStore = fixtureHTML == nil ? .default() : .nonPersistent()
        config.userContentController.addUserScript(WKUserScript(source: BrowserAudioBuffer.script, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page))
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.uiDelegate = self; webView.navigationDelegate = self
    }
    private func prepareWindow() {
        if window == nil {
            let value = ConnectionWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 740), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            value.title = "FlowGpt · ChatGPT connection"
            value.isReleasedWhenClosed = false; value.contentView = webView; value.center()
            window = value
            hide()
            loadHome()
        }
    }
    private func loadHome() {
        if let fixtureHTML { webView.loadHTMLString(fixtureHTML, baseURL: home) }
        else { webView.load(URLRequest(url: home)) }
    }
    private func reloadPage() {
        if let fixtureHTML { webView.loadHTMLString(fixtureHTML, baseURL: home) }
        else { webView.reload() }
    }
    func restoreConnection() {
        prepareWindow()
        guard health == nil else { return }
        health = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                await self?.checkConnection()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.checkConnection() }
        }
    }
    func shutdown() {
        health?.cancel(); health = nil; connectionCheck?.cancel()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver); self.wakeObserver = nil }
    }
    func checkConnection() async {
        guard !owned else { return }
        if webView.isLoading, ProcessInfo.processInfo.systemUptime - navigationStartedAt < 30 { return }
        if let state = try? await evaluate("state", ignorePageError: true) {
            if state["login"] as? Bool == true { connected = false; connectionMessage = "Sign in to ChatGPT again"; return }
            if !(state["text"] as? String ?? "").isEmpty { return }
            if state["recording"] as? Bool == true || state["transcribing"] as? Bool == true { return }
            if state["ready"] as? Bool == true {
                lastError = nil
                if state["temporary"] as? Bool != true { _ = try? await evaluate("prepare"); return }
                lastError = nil; connected = true; connectionMessage = "ChatGPT connected"; recovery.ready(); return
            }
        }
        // Never repeatedly reload a login/authorization page.
        guard webView.url?.host == "chatgpt.com" else { connected = false; connectionMessage = "Finish signing in to ChatGPT"; return }
        guard lastError != nil || ProcessInfo.processInfo.systemUptime - navigationStartedAt >= 20 else { return }
        if recovery.request(now: ProcessInfo.processInfo.systemUptime, active: owned, needsLogin: false, hasDraft: observedDraft) {
            connected = false; connectionMessage = "Reconnecting to ChatGPT…"; lastError = nil
            recoveryReloads += 1; webView.stopLoading(); reloadPage()
        }
    }
    func show() {
        prepareWindow()
        window?.rendersInBackground = false
        window?.ignoresMouseEvents = false
        window?.alphaValue = 1
        window?.center()
        window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func hide() {
        guard let window else { return }
        window.rendersInBackground = true
        window.ignoresMouseEvents = true
        if window.isMiniaturized { window.deminiaturize(nil) }
        // WebKit suspends microphone startup when its window is ordered out or
        // entirely offscreen. A transparent, non-foreground renderer keeps the
        // document live; the actual connection UI remains invisible.
        window.alphaValue = 0.001
        window.center()
        window.orderBack(nil)
    }
    var connectionWindowVisible: Bool {
        guard let window, window.isVisible, window.alphaValue >= 0.01 else { return false }
        return NSScreen.screens.contains { $0.frame.intersects(window.frame) }
    }
    func reload() {
        guard !owned else { return }
        prepareWindow(); lastError = nil; connected = false
        connectionMessage = "Reconnecting…"; reloadPage()
    }
    private func checkOrigin(ignorePageError: Bool = false) throws {
        guard let url = webView.url, url.scheme == "https", url.host == "chatgpt.com" else {
            throw BrowserBridgeError.unavailable("Open the ChatGPT connection window and finish signing in.")
        }
        if !ignorePageError, let lastError { throw BrowserBridgeError.unavailable(lastError) }
    }
    private func evaluate(_ action: String, expected: String = "", ignorePageError: Bool = false) async throws -> [String: Any] {
        try checkOrigin(ignorePageError: ignorePageError)
        let value = try await webView.callAsyncJavaScript(Self.script, arguments: ["action": action, "expected": expected], in: nil, contentWorld: .page)
        guard let result = value as? [String: Any] else { throw BrowserBridgeError.unavailable("ChatGPT returned an unreadable browser state.") }
        if let error = result["error"] as? String { throw BrowserBridgeError.unavailable(error) }
        if action == "state", result["hasEditor"] as? Bool == true { observedDraft = !(result["text"] as? String ?? "").isEmpty }
        return result
    }
    func start() async throws {
        guard !owned else { throw BrowserBridgeError.unavailable("A browser dictation is already active.") }
        let began = Date()
        prepareWindow()
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                throw BrowserBridgeError.unavailable("Microphone permission was not granted. Allow Flow in macOS Microphone settings.")
            }
        }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw BrowserBridgeError.unavailable("Flow needs microphone permission in macOS before ChatGPT can record.")
        }
        try Task.checkCancellation()
        try microphone.start()
        owned = true
        inputName = microphone.inputName
        captureStartMilliseconds = Date().timeIntervalSince(began) * 1_000
        metering = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                audioLevel = microphone.level
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
            }
        }
        // Keep the authenticated web engine alive without showing its window or
        // taking keyboard focus from the insertion destination.
        hide()
        startupError = nil; recorderReady = false; recorderStartMilliseconds = 0
        recorderStartup = Task { [weak self] in
            guard let self else { return }
            do {
                try Task.checkCancellation()
                try await waitForComposer()
                _ = try await evaluate("captureNative")
                audioPump = Task { [weak self] in
                    guard let self else { return }
                    do {
                        while !Task.isCancelled {
                            if let failure = microphone.failure { throw BrowserBridgeError.unavailable(failure) }
                            if let data = microphone.peek() {
                                _ = try await evaluate("feedAudio", expected: data.base64EncodedString())
                                microphone.acknowledge()
                            } else { try await Task.sleep(for: .milliseconds(20)) }
                        }
                    } catch { if !Task.isCancelled { startupError = error.localizedDescription } }
                }
                _ = try await evaluate("start")
                let deadline = Date().addingTimeInterval(20)
                while Date() < deadline {
                    try Task.checkCancellation()
                    let state = try await evaluate("state")
                    if state["recording"] as? Bool == true {
                        guard state["audioAttached"] as? Bool == true else { throw BrowserBridgeError.unavailable("ChatGPT did not use the buffered microphone. Recording was cancelled to protect the opening words.") }
                        _ = try await evaluate("playAudio")
                        recorderReady = true
                        recorderStartMilliseconds = Date().timeIntervalSince(began) * 1_000
                        return
                    }
                    try await Task.sleep(for: .milliseconds(80))
                }
                throw BrowserBridgeError.unavailable("ChatGPT did not start its recorder. Open Manage connection and retry.")
            } catch {
                if !Task.isCancelled { startupError = error.localizedDescription }
            }
        }
    }
    func finish() async throws -> String {
        guard owned else { throw BrowserBridgeError.unavailable("Flow does not own an active dictation.") }
        // Freeze input immediately, even if the website is still starting. Drain
        // all captured audio into its recorder before asking it to transcribe.
        microphone.stop()
        await recorderStartup?.value
        try Task.checkCancellation()
        if let startupError { throw BrowserBridgeError.unavailable(startupError) }
        let nativeDrainDeadline = Date().addingTimeInterval(10)
        while microphone.pendingBytes > 0, Date() < nativeDrainDeadline {
            try Task.checkCancellation()
            if let startupError { throw BrowserBridgeError.unavailable(startupError) }
            try await Task.sleep(for: .milliseconds(20))
        }
        guard microphone.pendingBytes == 0 else { throw BrowserBridgeError.unavailable("The connection could not accept all captured speech. No incomplete text was pasted.") }
        _ = try await evaluate("freezeAudio")
        let drainDeadline = Date().addingTimeInterval(32)
        var drained = false
        while Date() < drainDeadline {
            try Task.checkCancellation()
            let state = try await evaluate("state")
            guard state["audioFailed"] as? Bool != true else { throw BrowserBridgeError.unavailable("The startup audio buffer filled. Recording cancelled; no incomplete transcript was pasted.") }
            if (state["audioQueued"] as? Double ?? 0) <= 0 { drained = true; break }
            try await Task.sleep(for: .milliseconds(80))
        }
        guard drained else { throw BrowserBridgeError.unavailable("Captured audio could not finish playing into ChatGPT’s recorder. Retry the connection.") }
        // Allow the last Web Audio quantum to reach MediaRecorder before stopping.
        try await Task.sleep(for: .milliseconds(100))
        let initial = try await evaluate("state")
        if initial["recording"] as? Bool == true { _ = try await evaluate("stop") }
        else if initial["ready"] as? Bool != true && initial["transcribing"] as? Bool != true {
            throw BrowserBridgeError.unavailable("ChatGPT recording state changed. Check its connection window.")
        }
        let deadline = Date().addingTimeInterval(120)
        var completion = TranscriptCompletion()
        while Date() < deadline {
            try Task.checkCancellation()
            let state = try await evaluate("state")
            let text = (state["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if state["ready"] as? Bool == true, !text.isEmpty {
                if let completed = completion.observe(text: text, ready: true,
                    transcribing: state["transcribing"] as? Bool == true,
                    recording: state["recording"] as? Bool == true,
                    at: Date().timeIntervalSinceReferenceDate) { return completed }
            } else {
                _ = completion.observe(text: text, ready: false, transcribing: true, recording: false, at: Date().timeIntervalSinceReferenceDate)
                if state["ready"] as? Bool == true { throw BrowserBridgeError.unavailable("ChatGPT returned no speech. No text was saved or pasted.") }
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw BrowserBridgeError.unavailable("ChatGPT transcription timed out. Check its browser window; Flow has not pasted anything.")
    }
    func finishedInPage() async -> Bool {
        guard owned else { return false }
        if startupError != nil { return true }
        if let failure = microphone.failure { startupError = failure; return true }
        guard recorderReady else { return false }
        guard let state = try? await evaluate("state") else { return false }
        if state["audioFailed"] as? Bool == true { startupError = "The microphone startup buffer filled. Retry the connection."; return true }
        return state["ready"] as? Bool == true || state["transcribing"] as? Bool == true
    }
    func discard(_ expected: String) async throws {
        defer { owned = false; audioLevel = 0 }
        await releaseAudio()
        _ = try await evaluate("discard", expected: expected)
    }
    func cancel() async {
        guard owned else { return }
        recorderStartup?.cancel(); await recorderStartup?.value; recorderStartup = nil
        // Do not throw away returned text if transcription already finished.
        _ = try? await evaluate("cancel")
        await releaseAudio()
        owned = false; audioLevel = 0; recorderReady = false
    }
    private func releaseAudio() async {
        microphone.cancel()
        metering?.cancel(); metering = nil
        audioPump?.cancel(); await audioPump?.value; audioPump = nil
        guard webView.url?.scheme == "https", webView.url?.host == "chatgpt.com" else { return }
        // Cleanup must still run after a navigation/DOM error. A stored page error
        // blocks normal actions, but must not leave our owned microphone alive.
        _ = try? await webView.callAsyncJavaScript("await window.__flowAudio?.end(); return true;", arguments: [:], in: nil, contentWorld: .page)
    }
    private func waitForComposer() async throws {
        let deadline = Date().addingTimeInterval(20)
        var prepared = false
        while Date() < deadline {
            try Task.checkCancellation()
            let state = try? await evaluate("state", ignorePageError: true)
            if state?["login"] as? Bool == true { connected = false; connectionMessage = "Sign in to ChatGPT again"; throw BrowserBridgeError.unavailable(connectionMessage) }
            guard !observedDraft else { throw BrowserBridgeError.unavailable("The ChatGPT composer contains a draft. Clear it before recording.") }
            if let state, state["ready"] as? Bool == true {
                lastError = nil
                guard (state["text"] as? String ?? "").isEmpty else { throw BrowserBridgeError.unavailable("The ChatGPT composer contains a draft. Clear it before recording.") }
                if state["temporary"] as? Bool == true { connected = true; return }
                if !prepared { _ = try await evaluate("prepare"); prepared = true }
            } else if lastError != nil, !webView.isLoading {
                lastError = nil; connected = false; connectionMessage = "Reconnecting…"
                loadHome(); prepared = false
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw BrowserBridgeError.unavailable("ChatGPT did not reconnect within 20 seconds. Captured audio was not submitted as an incomplete transcript.")
    }
    private func navigationFailed(_ error: any Error) {
        guard !BrowserConnectionRecovery.cancelledNavigation(error) else { return }
        lastError = error.localizedDescription; connected = false; connectionMessage = "Connection interrupted; retrying…"
        if owned && recorderReady { startupError = "The connection was interrupted. Captured speech was not silently discarded or pasted as complete." }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { navigationFailed(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { navigationFailed(error) }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        navigationStartedAt = ProcessInfo.processInfo.systemUptime
        connected = false; connectionMessage = "Connecting to ChatGPT…"
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        lastError = nil
        connectionCheck?.cancel()
        connectionCheck = Task { [weak self] in
            guard let self else { return }
            for _ in 0..<100 {
                if Task.isCancelled { return }
                if let state = try? await evaluate("state"), state["ready"] as? Bool == true {
                    if !owned, state["temporary"] as? Bool != true, (state["text"] as? String ?? "").isEmpty {
                        _ = try? await evaluate("prepare")
                    } else {
                        connected = state["temporary"] as? Bool == true
                        connectionMessage = connected ? "ChatGPT connected" : "Open an empty Temporary Chat"
                        return
                    }
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
            connected = false; connectionMessage = "Sign in or check the ChatGPT connection"
        }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        lastError = "ChatGPT browser stopped"; connected = false; connectionMessage = "Reconnecting after browser interruption…"
        if owned && audioPump != nil { startupError = "ChatGPT’s renderer stopped while dictating. No incomplete text was pasted." }
        else if !owned { Task { [weak self] in await self?.checkConnection() } }
    }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void) {
        guard origin.protocol == "https", origin.host == "chatgpt.com", frame.isMainFrame, type == .microphone else { decisionHandler(.deny); return }
        // The OS grant remains mandatory. Only an explicit Flow recording can
        // delegate that microphone to ChatGPT. Idle pages cannot re-prompt on launch.
        decisionHandler(BrowserMicrophoneConsent.mayDelegate(recordingOwned: owned, osAuthorized: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized) ? .grant : .deny)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }
    // Current labels were observed on a signed-in ChatGPT page on 2026-10-13.
    // Ambiguous controls fail closed; never click Send/Transcribe and send/Voice.
    static let script = #"""
    const visible = e => e && e.getClientRects().length > 0;
    const buttons = label => Array.from(document.querySelectorAll('button')).filter(e => visible(e) && e.getAttribute('aria-label') === label);
    const one = label => { const a = buttons(label); return a.length === 1 ? a[0] : null; };
    const editor = () => {
      const a = Array.from(document.querySelectorAll('[contenteditable="true"][role="textbox"], #prompt-textarea, textarea')).filter(visible);
      const unique = [...new Set(a)]; return unique.length === 1 ? unique[0] : null;
    };
    const text = () => { const e = editor(); if (!e) return ''; return (e.tagName === 'TEXTAREA' ? e.value : e.innerText).trim(); };
    const click = label => {
      const e = one(label);
      if (!e || e.disabled || e.getAttribute('aria-disabled') === 'true') return {error:'ChatGPT control unavailable: ' + label + '. Check the connection window.'};
      e.click(); return {ok:true};
    };
    const temporary = !!one('Turn off temporary chat');
    const mic = one('Dictate');
    const ready = !!mic && !mic.disabled && mic.getAttribute('aria-disabled') !== 'true' && !!editor();
    if (action === 'state') {
      const a = window.__flowAudio?.state() || {};
      const login = Array.from(document.querySelectorAll('button,a')).some(e => visible(e) && ['Log in','Sign in'].includes(e.textContent.trim()));
      return {temporary, login, hasEditor:!!editor(), recording:!!one('Stop dictation') && !one('Stop dictation').disabled && !!one('Cancel dictation'), transcribing:!!one('Cancel transcription'), ready, text:text(), audioLevel:a.level || 0, audioQueued:a.queued || 0, audioFailed:!!a.failed, audioAttached:!!a.attached};
    }
    if (action === 'capture') { if (!window.__flowAudio) return {error:'The microphone bridge did not load. Reload the connection.'}; return await window.__flowAudio.begin(); }
    if (action === 'captureNative') { if (!window.__flowAudio) return {error:'The microphone bridge did not load. Reload the connection.'}; return await window.__flowAudio.begin(true); }
    if (action === 'feedAudio') { if (!window.__flowAudio?.state().active) return {error:'The audio renderer disconnected. Captured audio was not acknowledged.'}; window.__flowAudio.push(expected); return {ok:true}; }
    if (action === 'playAudio') { window.__flowAudio?.play(); return {ok:true}; }
    if (action === 'freezeAudio') { window.__flowAudio?.stop(); return {ok:true}; }
    if (action === 'endAudio') { await window.__flowAudio?.end(); return {ok:true}; }
    if (action === 'prepare') {
      if (!one('Dictate') || !editor()) return {error:'Sign into ChatGPT and open a new empty chat with a Dictate button.'};
      if (text()) return {error:'The ChatGPT composer contains a draft. Flow will not overwrite it. Clear it yourself first.'};
      if (temporary) return {ok:true};
      return click('Temporary chat');
    }
    if (action === 'start') {
      if (!temporary) return {error:'Temporary Chat is not verified. Flow will not use a regular conversation automatically.'};
      if (text()) return {error:'The ChatGPT composer contains a draft. Clear it first.'};
      return click('Dictate');
    }
    if (action === 'stop') return click('Stop dictation');
    if (action === 'cancel') {
      for (const label of ['Cancel dictation','Starting dictation; click to cancel','Cancel transcription']) if (one(label)) return click(label);
      return {ok:true};
    }
    if (action === 'discard') {
      const e = editor();
      if (!e || text() !== expected) return {error:'The ChatGPT draft changed; it was preserved.'};
      e.focus();
      if (e.tagName === 'TEXTAREA') {
        Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype,'value').set.call(e,'');
        e.dispatchEvent(new Event('input',{bubbles:true}));
      } else { document.execCommand('selectAll',false); document.execCommand('delete',false); }
      if (text()) return {error:'ChatGPT kept the draft. Clear it before the next recording.'};
      return {ok:true};
    }
    return {error:'Unknown bridge action'};
    """#
}
