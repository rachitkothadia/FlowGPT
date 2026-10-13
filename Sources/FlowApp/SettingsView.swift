import SwiftUI
import ServiceManagement
import FlowCore

private enum SettingsPage: String, CaseIterable, Identifiable {
    case setup = "Get Started", general = "General", shortcuts = "Shortcuts", speech = "Speech", processing = "Text Processing", privacy = "Privacy", connection = "Connection", history = "History", about = "About"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .setup: "sparkles"
        case .general: "gearshape"
        case .shortcuts: "keyboard"
        case .speech: "mic"
        case .processing: "text.alignleft"
        case .privacy: "hand.raised"
        case .connection: "network"
        case .history: "clock"
        case .about: "info.circle"
        }
    }
}
struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var page: SettingsPage? = .setup
    @State private var showKey = false
    @State private var clearConfirmation = false
    @State private var capture = false
    @State private var monitor: Any?
    @State private var shortcutNotice = ""
    var body: some View {
        let _ = model.revision
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().frame(width: 48, height: 48).accessibilityHidden(true)
                Text("Flow").font(.system(size: 30, weight: .bold, design: .rounded))
                Button {
                    withAnimation {
                        columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .buttonStyle(.plain)
                .padding(6)
                .help(columnVisibility == .detailOnly ? "Show sidebar" : "Hide sidebar")
                .accessibilityLabel(columnVisibility == .detailOnly ? "Show sidebar" : "Hide sidebar")
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()
            NavigationSplitView(columnVisibility: $columnVisibility) {
            List(SettingsPage.allCases, selection: $page) { item in
                Label(item.rawValue, systemImage: item.symbol).tag(item)
            }
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(ideal: 180)
            .safeAreaInset(edge: .bottom) {
                HStack { Image(systemName: "waveform").foregroundStyle(.tint); Text("Flow").fontWeight(.semibold); Spacer(); Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development").foregroundStyle(.secondary) }.padding(16)
            }
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                Text((page ?? .setup).rawValue).font(.title2.weight(.semibold)).padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 8)
                if !model.notice.isEmpty {
                    HStack(alignment: .top) {
                        Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                        Text(model.notice).font(.callout)
                        Spacer()
                        Button { model.notice = "" } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss notice")
                    }.padding(12).background(.quaternary).padding(.horizontal, 24)
                }
                content
            }
        }
        }
        .tint(Color(red: 0.32, green: 0.48, blue: 0.41))
        .frame(minWidth: 760, minHeight: 570)
        .onChange(of: model.preferences) { old, _ in model.savePreferences(previous: old) }
        .onChange(of: model.resultRevision) { _, _ in page = .history }
        .onDisappear { stopCapture() }
        .onChange(of: page) { _, _ in stopCapture() }
        .confirmationDialog("Delete all saved dictations?", isPresented: $clearConfirmation) { Button("Delete History", role: .destructive) { model.clearHistory() } }
    }
    @ViewBuilder private var content: some View {
        switch page ?? .setup {
        case .setup: setup
        case .general: general
        case .shortcuts: shortcuts
        case .speech: speech
        case .processing: processing
        case .privacy: privacy
        case .connection: connection
        case .history: history
        case .about: about
        }
    }
    private var setup: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Speak. Keep your flow.").font(.largeTitle.weight(.semibold))
                    Text("Turn your voice into text wherever you work. Press the shortcut to start, speak naturally, then press it again to finish.").foregroundStyle(.secondary)
                    Text(model.preferences.shortcut.label).font(.title3.monospaced()).padding(.vertical, 8)
                }.padding(.vertical, 10)
            }
            apiKeySection
            Section("Allow the essentials") {
                permissionRow("Microphone", detail: "Record only when you start dictation.", granted: model.permissions.microphone) { Task { _ = await model.permissions.requestMicrophone(); model.recheckPermissions() } }
                permissionRow("Accessibility", detail: "Insert text into your focused field and capture the shortcut.", granted: model.permissions.accessibility) { model.permissions.requestAccessibility(); model.permissions.open("Accessibility") }
                permissionRow("Input Monitoring", detail: "Recognize the global shortcut while other apps are active.", granted: model.permissions.inputMonitoring) { model.permissions.requestInput(); model.permissions.open("ListenEvent") }
                HStack {
                    Button("Recheck Permissions") { model.recheckPermissions() }
                    Button("Restart Flow") { model.restart() }
                }
                Text("These indicators read fresh permission results from macOS. Flow reopens automatically if macOS needs a restart after granting Accessibility. After a local app update, macOS may still show an old grant as on. Toggle Flow off and on in System Settings to authorize the updated app, then recheck. Fn + Space can conflict with macOS keyboard settings; choose an alternative in Shortcuts.").font(.caption).foregroundStyle(.secondary)
            }

        }.formStyle(.grouped)
    }
    private func permissionRow(_ title: String, detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle").foregroundStyle(granted ? .green : .secondary).accessibilityLabel(granted ? "Granted" : "Not granted")
            VStack(alignment: .leading) { Text(title); Text(detail).font(.caption).foregroundStyle(.secondary) }
            Spacer(); Button(granted ? "Settings" : "Allow") {
                if granted { model.permissions.open(title == "Microphone" ? "Microphone" : title == "Accessibility" ? "Accessibility" : "ListenEvent") } else { action() }
            }
        }
    }
    private var general: some View {
        Form {
            Section("Availability") {
                Toggle("Start at Login", isOn: Binding(get: { _ = model.revision; return model.login.enabled }, set: { model.setLogin($0) }))
                Text(model.login.status).font(.caption).foregroundStyle(.secondary)
                Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                Toggle("Start quietly in the background", isOn: $model.preferences.backgroundLaunch)
            }
            Section("Dictation panel") {
                Toggle("Show floating panel", isOn: $model.preferences.showPanel)
                Toggle("Dismiss after completion", isOn: $model.preferences.autoDismiss)
                Text("Errors stay visible until dismissed. The menu bar always provides Stop and Cancel.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Appearance") {
                Picker("Appearance", selection: $model.preferences.appearance) { ForEach(["System", "Light", "Dark"], id: \.self) { Text($0) } }
            }
        }.formStyle(.grouped)
    }
    private var shortcuts: some View {
        Form {
            Section("Global shortcut") {
                Toggle("Enable shortcut", isOn: $model.preferences.shortcutEnabled)
                Picker("Shortcut", selection: $model.preferences.shortcut) {
                    Text(Shortcut.fnSpace.label).tag(Shortcut.fnSpace)
                    Text(Shortcut.fallback.label).tag(Shortcut.fallback)
                    Text(Shortcut.commandShiftD.label).tag(Shortcut.commandShiftD)
                    if ![Shortcut.fnSpace, .fallback, .commandShiftD].contains(model.preferences.shortcut) { Text(model.preferences.shortcut.label).tag(model.preferences.shortcut) }
                }
                Button(capture ? "Press a key combination… (Escape cancels)" : "Record Custom Shortcut") { startCapture() }
                if !shortcutNotice.isEmpty { Text(shortcutNotice).font(.caption).foregroundStyle(.secondary) }
                Toggle("Push to talk", isOn: $model.preferences.pushToTalk)
                Text(model.preferences.pushToTalk ? "Hold to record. Release the key or modifiers to finish." : "Press once to record and again to finish. Presses during processing are ignored.").font(.caption).foregroundStyle(.secondary)
                Button("Reset to Fn + Space") { model.preferences.shortcut = .fnSpace }
            }
            Section("System access") {
                Text("Fn / Globe shortcuts may be intercepted by macOS. Review System Settings → Keyboard → Keyboard Shortcuts. Flow cannot discover every shortcut used by another app.")
                Button("Recheck Permissions and Enable") { model.recheckPermissions() }
            }
        }.formStyle(.grouped)
    }
    private func startCapture() {
        stopCapture(); capture = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let suppress = MainActor.assumeIsolated {
                if event.keyCode == 53 { stopCapture(); return true }
                let flags = event.modifierFlags.rawValue & UInt(Shortcut.modifierMask)
                let label = [(NSEvent.ModifierFlags.command, "Command"), (.control, "Control"), (.option, "Option"), (.shift, "Shift"), (.function, "Fn")].compactMap { event.modifierFlags.contains($0.0) ? $0.1 : nil }.joined(separator: " + ") + " + " + (event.keyCode == 49 ? "Space" : (event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"))
                let shortcut = Shortcut(keyCode: event.keyCode, modifiers: UInt64(flags), label: label)
                guard shortcut.isValid else { shortcutNotice = "Use a modifier with an ordinary key."; return true }
                let commonReserved = event.modifierFlags.contains(.command) && [12, 48, 49, 9, 8, 0, 46, 13, 4].contains(event.keyCode)
                guard !commonReserved else { shortcutNotice = "This combination is commonly reserved by macOS or editing commands. Choose another."; return true }
                model.preferences.shortcut = shortcut; shortcutNotice = "Saved. Test it in your destination app to check for conflicts."; stopCapture(); return true
            }
            return suppress ? nil : event
        }
    }
    private func stopCapture() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil; capture = false }
    private var speech: some View {
        Form {
            Section("Transcription") {
                LabeledContent("Model", value: GroqRequest.speechModel(for: model.preferences))
                Picker("Spoken language", selection: $model.preferences.language) {
                    Text("Automatic").tag("")
                    ForEach(LanguageCatalog.indian.filter(\.dedicatedRecognition)) { language in Text(language.name).tag(language.code) }
                    ForEach(LanguageCatalog.otherLanguages) { language in Text(language.name).tag(language.code) }
                }
                Picker("Recognition", selection: Binding(get: { model.preferences.accuracy ?? "Accurate" }, set: { model.preferences.accuracy = $0 })) {
                    Text("Fast · Whisper Turbo").tag("Fast")
                    Text("Accuracy first · Whisper v3").tag("Accurate")
                }
                Text("Use Automatic for mixed languages. The listed Indian languages have dedicated Whisper language options; accuracy varies. Bodo, Dogri, Kashmiri, Konkani, Maithili, Manipuri, Odia and Santali have no dedicated Whisper option and are not verified for speech recognition. Flow preserves their scripts when text is returned.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Recording") {
                Toggle("Continuous lecture / meeting recording", isOn: Binding(get: { model.preferences.isContinuous }, set: { model.preferences.continuous = $0 }))
                if model.preferences.isContinuous {
                    Picker("Audio source", selection: Binding(get: { model.preferences.audioSource ?? "Microphone" }, set: { model.preferences.audioSource = $0 })) {
                        Text("Microphone · in-person lecture").tag("Microphone")
                        Text("Computer audio · online lecture").tag("Computer audio")
                    }
                }
                Text(model.preferences.isContinuous ? "Records continuously to private local WAV segments while transcription runs in the background. Audio and transcripts remain in your Recordings folder. No automatic time limit; disk space, hardware and API quotas still apply. Computer audio requires separate macOS recording permission and captures app audio, without saving screen images; it does not include your microphone." : "16 kHz mono WAV. Everyday dictation stops at 3 minutes; use continuous recording for longer sessions.")
                Button("Open Recordings Folder") { model.openRecordings() }
                Button("Open Sound Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!) }
            }
        }.formStyle(.grouped).disabled(model.session.state.busy)
    }
    private var processing: some View {
        Form {
            Section("Text cleanup") {
                Toggle("Format with GPT-OSS", isOn: $model.preferences.cleanup)
                Text("Whisper transcribes your speech. GPT-OSS adds punctuation, paragraphs, bullets and numbered steps across mixed languages. There are no local prediction or correction rules. Turn off to use the raw transcript.").font(.caption).foregroundStyle(.secondary)
                Picker("Default mode", selection: $model.preferences.mode) { ForEach(DictationMode.allCases, id: \.self) { Text($0.rawValue) } }
                if model.preferences.mode == .custom { TextField("Custom style instructions", text: $model.preferences.customInstructions, axis: .vertical).lineLimit(4...8) }
                Text(modeExplanation).font(.callout).foregroundStyle(.secondary)
                LabeledContent("Model", value: GroqRequest.textModel)
            }
        }.formStyle(.grouped)
    }
    private var modeExplanation: String {
        switch model.preferences.mode {
        case .clean: "Natural punctuation, spoken corrections, paragraphs and numbered lists when you enumerate. Preserves meaning, casual tone and language. No long dashes or added commentary."
        case .verbatim: "Preserves wording and fillers with essential punctuation."
        case .professional: "Uses clear punctuation and paragraphs while preserving your words and tone."
        case .developer: "Preserves identifiers, filenames and technical language. Never executes dictated text."
        case .custom: "Your style guidance applies within rules that preserve meaning and prevent added facts."
        }
    }
    private var privacy: some View {
        Form {
            Section("Your data") {
                Toggle("Save history on this Mac", isOn: $model.preferences.historyEnabled)
                Text("Off by default. Turning off deletes saved history. When enabled, up to 100 text results are stored locally with private file permissions, without encryption. Microphone recordings are never kept in history.").font(.caption).foregroundStyle(.secondary)
                Button("Clear History", role: .destructive) { clearConfirmation = true }
            }
            Section("Text insertion") {
                Text("Automatic insertion uses Accessibility where supported, or pastes into your original field and restores your clipboard. A newer clipboard change is kept.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Cloud processing") {
                        Text("Audio is sent only to api.groq.com. Cleanup sends transcript text to the same service. No analytics or idle background listening. Everyday temporary audio is removed after processing or cancellation. Continuous session audio and transcripts remain in your Recordings folder until you delete that folder. Older learning files are unused by Flow 4.0.")
                Button("Groq Data Policy") { NSWorkspace.shared.open(URL(string: "https://console.groq.com/docs/your-data")!) }
                Button("Export Private Diagnostics") { model.exportDiagnostics() }
            }
        }.formStyle(.grouped)
    }
    private var apiKeySection: some View {
        Section("Groq API key") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Enter your Groq API key").font(.headline)
                HStack {
                    Group {
                        if showKey { TextField("Paste your Groq API key here", text: keyBinding) }
                        else { SecureField("Paste your Groq API key here", text: keyBinding) }
                    }
                    .textFieldStyle(.roundedBorder).controlSize(.large)
                    .frame(maxWidth: .infinity).accessibilityLabel("Groq API key")
                    .disabled(model.testingConnection)
                    Button { showKey.toggle() } label: { Image(systemName: showKey ? "eye.slash" : "eye") }
                        .buttonStyle(.plain).help(showKey ? "Hide API key" : "Show API key")
                        .accessibilityLabel(showKey ? "Hide API key" : "Show API key")
                }
                if model.hasKey { Label("This key is used for dictation", systemImage: "key.fill").font(.caption).foregroundStyle(.secondary) }
                Button(model.testingConnection ? "Testing API Key…" : "Test API Key") {
                    model.testConnection(enteredKey: model.apiKey)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.testingConnection || !model.hasKey)
                if model.testingConnection { ProgressView().controlSize(.small) }
                probeRow("Whisper", model: GroqRequest.speechModel(for: Preferences()), result: model.speechProbe)
                probeRow("GPT-OSS 120B", model: GroqRequest.textModel, result: model.textProbe)
                if !model.connectionStatus.isEmpty { Text(model.connectionStatus).font(.callout).foregroundStyle(.secondary) }
                Text("Testing uses exactly the key shown above and sends a bundled speech sample and a fixed text prompt. Results clear when the key changes. The key saves automatically in your private Flow folder on this Mac, without encryption.")
                    .font(.caption).foregroundStyle(.secondary)
                if model.hasKey {
                    Button("Remove Saved Key", role: .destructive) { model.deleteKey() }
                        .disabled(model.testingConnection)
                }
            }.padding(.vertical, 6)
        }
    }
    private var keyBinding: Binding<String> { Binding(get: { model.apiKey }, set: { model.saveKey($0) }) }
    private func probeRow(_ title: String, model: String, result: ModelProbeResult?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: result?.passed == true ? "checkmark.circle.fill" : result == nil ? "circle" : "xmark.circle.fill")
                .foregroundStyle(result?.passed == true ? .green : result == nil ? .secondary : .red)
                .accessibilityLabel(result?.passed == true ? "Passed" : result == nil ? "Not tested" : "Failed")
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(model).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(result?.message ?? (self.model.testingConnection ? "Waiting…" : "Not tested"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var connection: some View {
        Form { apiKeySection }.formStyle(.grouped)
    }
    private var history: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("Continuous recordings") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.session.message).font(.callout)
                        Button("Open Recordings Folder") { model.openRecordings() }
                        ForEach(model.recordingFolders, id: \.path) { folder in
                            HStack {
                                Text(String(folder.lastPathComponent.prefix(8))).font(.caption.monospaced())
                                Button("Open") { NSWorkspace.shared.open(folder) }
                                Button("Recover Pending Audio") { model.recoverRecording(folder) }.disabled(model.session.state.busy || !model.hasKey)
                            }
                        }
                        Text("Complete transcripts are saved as Transcript.txt. Pending audio remains on this Mac. Recovery never inserts into another app. Active files left by a crash remain available for inspection.").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                if !model.session.finalText.isEmpty || !model.session.rawText.isEmpty {
                    GroupBox("Last result · available until you quit") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(model.session.finalText.isEmpty ? model.session.rawText : model.session.finalText).textSelection(.enabled)
                            HStack {
                                Button("Copy Final Text") { model.copy(model.session.finalText) }.disabled(model.session.finalText.isEmpty)
                                Button("Copy Raw Transcript") { model.copy(model.session.rawText) }.disabled(model.session.rawText.isEmpty)
                            }
                            Text("Use the floating panel or menu bar to retry insertion after returning to your original field.").font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                }
                if model.history.isEmpty {
                    ContentUnavailableView(model.preferences.historyEnabled ? "No saved dictations" : "History is off", systemImage: "clock", description: Text("Enable local history in Privacy to save future results."))
                }
                ForEach(model.history) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text(entry.date, style: .date); Text(entry.date, style: .time); Spacer(); Text(entry.mode.rawValue) }.font(.caption).foregroundStyle(.secondary)
                        Text(entry.final).textSelection(.enabled)
                        HStack { Button("Copy") { model.copy(entry.final) }; Button("Delete", role: .destructive) { model.deleteHistory(entry.id) } }
                        Divider()
                    }
                }
            }.padding(24)
        }
    }
    private var about: some View {
        Form {
            Section {
                Label("Flow", systemImage: "waveform").font(.title.weight(.semibold))
                LabeledContent("Version", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "local"))")
                Text("A personal voice dictation utility for macOS 14 and later. An original interface inspired by useful dictation workflows.")
                LabeledContent("Transcription", value: GroqRequest.speechModel(for: model.preferences))
                LabeledContent("Text processing", value: GroqRequest.textModel)
            }
            Section("Support") {
                Button("Open User Guide") {
                    if let url = Bundle.main.url(forResource: "UserGuide", withExtension: "md") { NSWorkspace.shared.open(url) }
                }
                Button("Export Diagnostics") { model.exportDiagnostics() }
                Button("Quit Flow") { NSApp.terminate(nil) }
            }
        }.formStyle(.grouped)
    }
}
