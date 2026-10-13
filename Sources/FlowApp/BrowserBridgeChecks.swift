import AppKit
import WebKit
import FlowCore
import AVFoundation
import ApplicationServices
import CoreAudio

/// Real WebKit DOM tests with a simulated ChatGPT page, not a live speech test.
@MainActor enum BrowserBridgeChecks {
    static func checkHiddenRecording() {
        let browser = ChatGPTBrowser()
        browser.restoreConnection()
        let original = NSWorkspace.shared.frontmostApplication?.processIdentifier
        Task {
            var report: [String: Any] = ["type": "Live ChatGPT hidden-window microphone check",
                "microphone": AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
                "accessibility": AXIsProcessTrusted(), "inputMonitoring": CGPreflightListenEventAccess()]
            do {
                guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { throw BrowserBridgeError.unavailable("Microphone permission is pending. This diagnostic does not request or change it.") }
                for _ in 0..<250 {
                    if browser.connected { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                report["outputBefore"] = outputSnapshot()
                try await browser.start()
                for _ in 0..<200 {
                    if browser.recorderStartMilliseconds > 0 { break }
                    if await browser.finishedInPage() { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                _ = await browser.finishedInPage()
                report["captureStartMilliseconds"] = browser.captureStartMilliseconds
                report["recorderStartMilliseconds"] = browser.recorderStartMilliseconds
                report["firstAudioFrameMilliseconds"] = browser.firstFrameMilliseconds
                report["input"] = browser.inputName
                report["outputDuring"] = outputSnapshot()
                report["microphoneActive"] = browser.nativeCaptureActive
                report["browserWindowHidden"] = !browser.connectionWindowVisible
                report["destinationFocusPreserved"] = NSWorkspace.shared.frontmostApplication?.processIdentifier == original
                report["passed"] = report["microphoneActive"] as? Bool == true && browser.recorderStartMilliseconds > 0 && report["browserWindowHidden"] as? Bool == true && report["destinationFocusPreserved"] as? Bool == true
            } catch {
                report["passed"] = false; report["error"] = error.localizedDescription
                report["captureState"] = browser.webView.microphoneCaptureState.rawValue
                report["documentVisibility"] = try? await browser.webView.evaluateJavaScript("document.visibilityState")
            }
            await browser.cancel()
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: "/tmp/flowgpt-recording-check.json"), options: .atomic)
            }
            NSApp.terminate(nil)
        }
    }
    static func checkNativeTiming() {
        Task {
            var report: [String: Any] = ["type": "Real native microphone cold/warm timings; no account or upload"]
            do {
                guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { throw BrowserBridgeError.unavailable("Authorize Microphone for the installed FlowGpt build first; this check does not change permissions.") }
                let microphone = NativeBrowserMicrophone()
                var runs: [[String: Any]] = []
                for number in 1...5 {
                    try microphone.start()
                    for _ in 0..<100 {
                        if microphone.firstFrameMilliseconds != nil { break }
                        try await Task.sleep(for: .milliseconds(10))
                    }
                    let first = microphone.firstFrameMilliseconds ?? 10_000
                    runs.append(["run": number, "engineStartMs": microphone.startMilliseconds, "firstAudioFrameMs": first, "input": microphone.inputName, "pendingBytes": microphone.pendingBytes, "failure": microphone.failure ?? "", "underOneSecond": first < 1_000 && microphone.startMilliseconds < 1_000])
                    microphone.cancel()
                    try await Task.sleep(for: .milliseconds(100))
                }
                report["runs"] = runs
                report["passed"] = runs.allSatisfy { $0["underOneSecond"] as? Bool == true }
            } catch { report["passed"] = false; report["error"] = error.localizedDescription }
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: URL(fileURLWithPath: "/tmp/flowgpt-native-timing.json"), options: .atomic) }
            NSApp.terminate(nil)
        }
    }
    static func checkRecovery() {
        let html = "<html><body><button aria-label='Turn off temporary chat'>Temporary</button><div contenteditable='true' role='textbox' id='editor'></div><button aria-label='Dictate' id='mic'>Mic</button></body></html>"
        let browser = ChatGPTBrowser(fixtureHTML: html)
        browser.restoreConnection()
        Task {
            var checks: [String: Bool] = [:]
            for _ in 0..<100 { if browser.connected { break }; try? await Task.sleep(for: .milliseconds(50)) }
            checks["initialReady"] = browser.connected
            browser.webView(browser.webView, didFailProvisionalNavigation: nil, withError: URLError(.cancelled))
            await browser.checkConnection()
            checks["cancelledNavigationKeepsConnection"] = browser.connected && browser.recoveryReloads == 0
            _ = try? await browser.webView.evaluateJavaScript("document.getElementById('mic').remove()")
            browser.webViewWebContentProcessDidTerminate(browser.webView)
            for _ in 0..<100 { if browser.connected && browser.recoveryReloads > 0 { break }; try? await Task.sleep(for: .milliseconds(50)) }
            checks["rendererFailureReloadsAndRecovers"] = browser.connected && browser.recoveryReloads == 1
            _ = try? await browser.webView.evaluateJavaScript("document.getElementById('editor').innerText='Protected fixture draft'; document.getElementById('mic').remove()")
            browser.webView(browser.webView, didFailProvisionalNavigation: nil, withError: URLError(.notConnectedToInternet))
            await browser.checkConnection()
            checks["draftPreventsReload"] = browser.recoveryReloads == 1
            let draft = try? await browser.webView.evaluateJavaScript("document.getElementById('editor').innerText")
            checks["draftPreserved"] = draft as? String == "Protected fixture draft"
            _ = try? await browser.webView.evaluateJavaScript("document.body.innerHTML='<button>Log in</button>'")
            await browser.checkConnection()
            checks["expiredLoginDoesNotReloadLoop"] = !browser.connected && browser.recoveryReloads == 1 && browser.connectionMessage.contains("Sign in")
            browser.shutdown()
            let report: [String: Any] = ["type": "Production connection manager with isolated nonpersistent WebKit fixture", "checks": checks, "passed": checks.count == 6 && checks.values.allSatisfy { $0 }]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: URL(fileURLWithPath: "/tmp/flowgpt-recovery-check.json"), options: .atomic) }
            NSApp.terminate(nil)
        }
    }
    private static func outputSnapshot() -> [String: Any] {
        var device = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var property = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, &device) == noErr else { return [:] }
        var result: [String: Any] = ["device": device]
        for channel in [UInt32(0), 1, 2] {
            property = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: channel)
            var level: Float32 = 0; size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(device, &property, 0, nil, &size, &level) == noErr { result["volume\(channel)"] = level }
        }
        return result
    }
    static func run() {
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let window = NSWindow(contentRect: web.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Flow bridge DOM checks"; window.contentView = web
        window.orderFront(nil)
        web.loadHTMLString(#"""
        <!doctype html><html><body>
        <button aria-label="Temporary chat" onclick="this.setAttribute('aria-label','Turn off temporary chat')">Temporary</button>
        <div role="textbox" contenteditable="true"></div>
        <button aria-label="Dictate" id="mic" onclick="document.querySelector('[role=textbox]').style.display='none';this.style.display='none';document.getElementById('stop').style.display='inline';document.getElementById('cancel').style.display='inline'">Mic</button>
        <button aria-label="Stop dictation" id="stop" style="display:none" onclick="document.querySelector('[role=textbox]').style.display='block';document.querySelector('[role=textbox]').innerText='नमस्ते hello';document.getElementById('mic').style.display='inline';this.style.display='none';document.getElementById('cancel').style.display='none'">Stop</button>
        <button aria-label="Cancel dictation" id="cancel" style="display:none" onclick="document.querySelector('[role=textbox]').style.display='block';document.getElementById('mic').style.display='inline';this.style.display='none';document.getElementById('stop').style.display='none'">Cancel</button>
        <button aria-label="Transcribe and send" onclick="document.body.dataset.sent='yes'">Never click</button>
        <button aria-label="Send" onclick="document.body.dataset.sent='yes'">Never click</button>
        </body></html>
        """#, baseURL: URL(string: "https://fixture.invalid"))
        Task {
            var checks: [String: Bool] = [:]
            do {
                for _ in 0..<100 {
                    if !web.isLoading, web.url != nil { break }
                    try await Task.sleep(for: .milliseconds(50))
                }
                @MainActor func action(_ action: String, _ expected: String = "") async throws -> [String: Any] {
                    try await web.callAsyncJavaScript(ChatGPTBrowser.script, arguments: ["action": action, "expected": expected], in: nil, contentWorld: .page) as? [String: Any] ?? [:]
                }
                let blocked = try await action("start"); checks["regularChatRefused"] = blocked["error"] != nil
                _ = try await action("prepare")
                let ready = try await action("state"); checks["temporaryVerified"] = ready["temporary"] as? Bool == true
                _ = try await action("start")
                let recording = try await action("state"); checks["recordingAcknowledged"] = recording["recording"] as? Bool == true
                _ = try await action("stop")
                let finished = try await action("state"); checks["mixedScriptReadVerbatim"] = finished["text"] as? String == "नमस्ते hello"
                let protected = try await action("discard", "wrong draft"); checks["changedDraftPreserved"] = protected["error"] != nil
                let draftBlocked = try await action("start"); checks["existingDraftRefused"] = draftBlocked["error"] != nil
                _ = try await action("discard", "नमस्ते hello")
                let empty = try await action("state"); checks["matchingDraftCleared"] = empty["text"] as? String == ""
                _ = try await action("start"); _ = try await action("cancel")
                let cancelled = try await action("state"); checks["cancelStopsRecording"] = cancelled["recording"] as? Bool == false
                let sent = try await web.evaluateJavaScript("document.body.dataset.sent || 'no'")
                checks["neverSentMessage"] = sent as? String == "no"
                let unknown = try await action("send"); checks["unknownActionRefused"] = unknown["error"] != nil
                let audioChecks = try await checkAudioBuffer(web)
                for (key, value) in audioChecks { checks[key] = value }
                let fallbackChecks = try await checkAudioBuffer(web, forceFallback: true)
                for (key, value) in fallbackChecks { checks["fallback_" + key] = value }
                for fallback in [false, true] {
                    let nativeChecks = try await checkAudioBuffer(web, forceFallback: fallback, native: true)
                    for (key, value) in nativeChecks { checks[(fallback ? "nativeFallback_" : "native_") + key] = value }
                }
            } catch { checks["exception"] = false; print(error.localizedDescription) }
            let passed = checks.count == 50 && checks.values.allSatisfy { $0 }
            let report: [String: Any] = ["passed": passed, "checks": checks, "type": "WebKit fixture; no real speech or account"]
            var detailed = report
            detailed["audioFixture"] = try? await web.evaluateJavaScript("window.__audioFixtureDebug || {}")
            if let data = try? JSONSerialization.data(withJSONObject: detailed, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: "/tmp/flow-browser-dom-check.json"), options: .atomic)
            }
            window.orderOut(nil); NSApp.terminate(nil)
        }
    }

    /// Real Web Audio/MediaRecorder with synthetic input, never the user's mic.
    private static func checkAudioBuffer(_ web: WKWebView, forceFallback: Bool = false, native: Bool = false) async throws -> [String: Bool] {
        let fixtureSetup = #"""
        if (window.__flowAudio) { await window.__flowAudio.end(); delete window.__flowAudio; }
        window.__fixtureAudioContext = new AudioContext();
        await window.__fixtureAudioContext.resume();
        const ctx = window.__fixtureAudioContext;
        const tone = ctx.createOscillator(); tone.frequency.value = 440;
        const dest = ctx.createMediaStreamDestination(); tone.connect(dest); tone.start();
        window.__fixtureAudioStream = dest.stream;
        window.__fixtureMicRequests = 0; window.__fixtureBuiltinChosen = false; window.__fixtureSpeakerConnections = 0;
        const connect = AudioNode.prototype.connect;
        AudioNode.prototype.connect = function(target, ...args) { if (target instanceof AudioDestinationNode) window.__fixtureSpeakerConnections++; return connect.call(this, target, ...args); };
        // Retain the DOM wrapper across native evaluations: WebKit can collect
        // an unretained wrapper and lose its fixture method overrides.
        window.__fixtureMedia = navigator.mediaDevices;
        window.__fixtureMedia.enumerateDevices = async () => [{kind:'audioinput', label:'MacBook Pro Microphone', deviceId:'fixture-builtin'}, {kind:'audioinput', label:'Bluetooth Headset', deviceId:'fixture-bluetooth'}];
        window.__fixtureMedia.getUserMedia = async options => { window.__fixtureMicRequests++; window.__fixtureBuiltinChosen = options.audio.deviceId.exact === 'fixture-builtin'; return dest.stream; };
        if (forceFallback && window.AudioWorklet) {
          window.__fixtureAddModule = AudioWorklet.prototype.addModule;
          AudioWorklet.prototype.addModule = async () => { throw Error('Fixture: worklet blocked by CSP'); };
        }
        return true;
        """#
        _ = try await web.callAsyncJavaScript(fixtureSetup, arguments: ["forceFallback": forceFallback], in: nil, contentWorld: .page)
        // The production script is origin-scoped. This local fixture is the only
        // place where that origin guard is removed; no real account is loaded.
        _ = try await web.evaluateJavaScript(BrowserAudioBuffer.script.replacingOccurrences(of: "location.origin !== 'https://chatgpt.com' || ", with: ""))
        let exercise = BrowserAudioBuffer.queue + #"""
        const results = {};
        const q = new FlowAudioQueue(16);
        const out = new Float32Array(3);
        q.process(new Float32Array([1,2,3]), out);
        results.openingBufferedBeforeRecorder = q.count === 3 && out.every(v => v === 0);
        q.playing = true; q.process(new Float32Array([4,5,6]), out);
        const first = Array.from(out); q.stopped = true; q.process(new Float32Array([99,99,99]), out);
        results.openingThenLiveInExactOrder = first.join(',') === '1,2,3' && Array.from(out).join(',') === '4,5,6';
        results.stopExcludesSubsequentSpeech = q.count === 0;
        const full = new FlowAudioQueue(2); full.process(new Float32Array([1,2,3]), out);
        results.overflowReportedWithoutPartialPlayback = full.failed && out.every(v => v === 0);
        const a = window.__flowAudio;
        results.noCaptureBeforeExplicitStart = window.__fixtureMicRequests === 0 && !a.state().active;
        await a.begin(native);
        if (native) {
          const wave = new Float32Array(4800);
          for (let i = 0; i < wave.length; i++) wave[i] = Math.sin(2 * Math.PI * 440 * i / 16000) * 0.5;
          const bytes = new Uint8Array(wave.buffer);
          let binary = ''; for (const byte of bytes) binary += String.fromCharCode(byte);
          a.push(btoa(binary));
        }
        for (let i = 0; i < 100 && (a.state().queued === 0 || (!native && a.state().level === 0)); i++) await new Promise(r => setTimeout(r, 20));
        const buffered = a.state();
        results.realAudioLevelsAndPrefix = (native || buffered.level > 0) && buffered.queued > 0;
        const stream = await navigator.mediaDevices.getUserMedia({audio:true});
        results.builtinAndOneMicrophoneOnly = (native ? window.__fixtureMicRequests === 0 : window.__fixtureBuiltinChosen && window.__fixtureMicRequests === 1) && a.state().attached;
        const recorder = new MediaRecorder(stream), chunks = [];
        const ended = new Promise(resolve => { recorder.ondataavailable = e => chunks.push(e.data); recorder.onstop = resolve; });
        recorder.start(); a.play();
        await new Promise(r => setTimeout(r, 300));
        a.stop();
        for (let i = 0; i < 100 && a.state().queued > 0; i++) await new Promise(r => setTimeout(r, 20));
        await new Promise(r => setTimeout(r, 100));
        results.bufferFullyDrained = a.state().queued === 0 && !a.state().failed;
        recorder.stop(); await ended;
        const decoded = await window.__fixtureAudioContext.decodeAudioData(await new Blob(chunks).arrayBuffer());
        const samples = decoded.getChannelData(0);
        let energy = 0; for (const value of samples) energy += value * value;
        results.recorderReceivesAudioWithoutSpeakerPlayback = Math.sqrt(energy / samples.length) > 0.01 && window.__fixtureSpeakerConnections === 0;
        await a.end();
        if (native) window.__fixtureAudioStream.getTracks().forEach(t => t.stop());
        results.cleanupStopsCaptureAndReleasesMemory = !a.state().active && window.__fixtureAudioStream.getTracks().every(t => t.readyState === 'ended');
        window.__audioFixtureDebug = {requests: window.__fixtureMicRequests, builtin: window.__fixtureBuiltinChosen, buffered, speakerConnections: window.__fixtureSpeakerConnections, tracks: window.__fixtureAudioStream.getTracks().map(t => t.readyState), ended: a.state(), documentVisibility: document.visibilityState};
        await window.__fixtureAudioContext.close();
        if (window.__fixtureAddModule) { AudioWorklet.prototype.addModule = window.__fixtureAddModule; delete window.__fixtureAddModule; }
        return results;
        """#
        return try await web.callAsyncJavaScript(exercise, arguments: ["native": native], in: nil, contentWorld: .page) as? [String: Bool] ?? [:]
    }
}
