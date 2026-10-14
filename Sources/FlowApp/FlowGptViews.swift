import AppKit
import SwiftUI
import FlowCore

private enum FlowGptPage: String, CaseIterable, Identifiable {
    case overview = "Home", history = "History", settings = "Settings", about = "About"
    var id: Self { self }
    var symbol: String {
        switch self { case .overview: "waveform"; case .history: "clock"; case .settings: "gearshape"; case .about: "info.circle" }
    }
}

struct BrowserBridgeView: View {
    @Bindable var model: BrowserBridgeModel
    @State private var selection: FlowGptPage? = .overview
    private let accent = Color(red: 0.18, green: 0.49, blue: 0.36)

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform").font(.title2.weight(.medium)).foregroundStyle(accent)
                        .frame(width: 38, height: 38).background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
                    Text("FlowGpt").font(.title3.weight(.semibold))
                }.padding(.horizontal, 18).padding(.top, 24).padding(.bottom, 22)
                List(FlowGptPage.allCases, selection: $selection) { page in
                    NavigationLink(value: page) { Label(page.rawValue, systemImage: page.symbol).padding(.vertical, 4) }
                }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.isDesignPreview ? "Design preview" : "FlowGpt " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"))
                    Text(connected ? "ChatGPT connected" : "Connection needed").foregroundStyle(.tertiary)
                }.font(.caption).foregroundStyle(.secondary).padding(20)
            }.navigationSplitViewColumnWidth(min: 190, ideal: 206, max: 230)
        } detail: {
            Group {
                switch selection ?? .overview {
                case .overview: overview
                case .history: FlowGptHistoryView(history: model.history)
                case .settings: settings
                case .about: about
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle((selection ?? .overview).rawValue)
        }
        .navigationSplitViewStyle(.balanced).tint(accent)
        .frame(minWidth: 760, minHeight: 550)
    }

    private var connected: Bool { model.isDesignPreview || model.browser.connected }
    private var allPermissions: Bool {
        model.isDesignPreview || (model.permissions.microphone && model.permissions.accessibility && model.permissions.inputMonitoring && !model.permissions.needsRestart)
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Dictate anywhere.").font(.system(size: 27, weight: .semibold)).tracking(-0.5)
                    Text("Click a text field, then press Fn + Space.").foregroundStyle(.secondary)
                }
                FlowGptCard {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Speak with a shortcut").font(.headline)
                                Text("Press once to record. Press again to finish.").foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 12)
                            HStack(spacing: 6) { keycap("fn"); Text("+").foregroundStyle(.tertiary); keycap("space") }
                        }
                        Divider()
                        HStack(spacing: 12) {
                            Image(systemName: connected && allPermissions ? "checkmark.circle.fill" : "circle.dotted")
                                .foregroundStyle(connected && allPermissions ? accent : .secondary)
                            Text(connected && allPermissions ? "Ready to record" : "Finish setup to start recording").foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            if !connected || !allPermissions { Button("Finish setup") { selection = .settings }.controlSize(.small) }
                        }
                        HStack {
                            Button(model.session.state == .recording ? "Finish recording" : "Try recording") { model.toggle(localPreview: true) }
                                .buttonStyle(.borderedProminent).controlSize(.large)
                                .disabled(model.session.state.busy && model.session.state != .recording)
                            if model.session.state.busy { Button("Cancel") { model.session.cancel() }.controlSize(.large) }
                            Spacer()
                        }
                        Text("Try recording saves text here. The shortcut types into the app you’re using.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if model.session.state != .idle {
                    Label(model.session.message, systemImage: model.session.state == .error ? "exclamationmark.circle" : "waveform")
                        .foregroundStyle(model.session.state == .error ? Color.orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !model.notice.isEmpty { Text(model.notice).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                HStack {
                    Text("Recent dictations").font(.headline)
                    Spacer()
                    Button("View history") { selection = .history }.buttonStyle(.link)
                }
                if model.history.isEmpty {
                    FlowGptEmptyView(symbol: "text.bubble", title: "A little space for your words", detail: "Your dictations will appear here after you finish speaking.")
                } else {
                    ForEach(Array(model.history.prefix(1))) { item in
                        FlowGptCard { FlowGptTranscriptView(item: item, compact: true) }
                    }
                }
            }.padding(30).frame(maxWidth: 820, alignment: .leading).frame(maxWidth: .infinity)
        }
    }

    private func keycap(_ label: String) -> some View {
        Text(label).font(.system(.body, design: .rounded).weight(.medium))
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Color(nsColor: .quaternaryLabelColor).opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel(label == "fn" ? "Function" : "Space")
    }

    private var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Set up FlowGpt").font(.system(size: 27, weight: .semibold)).tracking(-0.5)
                    Text("Your connection and recording permissions.").foregroundStyle(.secondary)
                }
                FlowGptCard {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "person.crop.circle").font(.system(size: 28)).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 9) {
                            Text("ChatGPT").font(.headline)
                            FlowGptStatusBadge(title: connected ? "Connected" : "Not connected", active: connected)
                            Text("Your saved connection is reused when you reopen FlowGpt.").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            HStack {
                                Button(connected ? "Manage connection" : "Continue with ChatGPT") { if !model.isDesignPreview { model.browser.show() } }
                                    .buttonStyle(.borderedProminent).disabled(model.session.state.busy)
                                Menu {
                                    Button("Reload connection") { if !model.isDesignPreview { model.browser.reload() } }
                                    Button("Hide connection window") { if !model.isDesignPreview { model.browser.hide() } }
                                } label: { Image(systemName: "ellipsis") }
                                .menuStyle(.borderlessButton).fixedSize().disabled(model.session.state.busy).accessibilityLabel("Connection options")
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                HStack {
                    Text("Allow the essentials").font(.headline)
                    Spacer()
                    Button { if !model.isDesignPreview { model.permissions.refresh() } } label: { Label("Refresh status", systemImage: "arrow.clockwise") }.controlSize(.small)
                }
                FlowGptCard {
                    VStack(spacing: 18) {
                        permissionRow("Microphone", detail: "Record only when you start dictation.", symbol: "mic", granted: model.permissions.microphone) {
                            Task { _ = await model.permissions.requestMicrophone() }
                        }
                        Divider()
                        permissionRow("Accessibility", detail: "Insert your words into the focused field.", symbol: "hand.raised", granted: model.permissions.accessibility) {
                            model.permissions.requestAccessibility(); model.permissions.open("Accessibility")
                        }
                        Divider()
                        permissionRow("Input Monitoring", detail: "Use the shortcut while another app is active.", symbol: "keyboard", granted: model.permissions.inputMonitoring) {
                            model.permissions.requestInput(); model.permissions.open("ListenEvent")
                        }
                    }
                }
                if model.permissions.needsRestart {
                    Label("Quit and reopen FlowGpt to activate macOS’s updated permission.", systemImage: "arrow.clockwise.circle")
                        .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                FlowGptCard {
                    Toggle("Start FlowGpt when I log in", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                    Text("Keep FlowGpt in the menu bar. Closing its window keeps dictation available.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(30).frame(maxWidth: 820, alignment: .leading).frame(maxWidth: .infinity)
        }
    }

    private var about: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("FlowGpt").font(.system(size: 27, weight: .semibold))
                    Text("Version " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.0")).foregroundStyle(.secondary)
                }
                FlowGptCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Updates").font(.headline)
                        Text(model.updater.message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Check for updates") { Task { await model.updater.check() } }.disabled(model.updater.busy || model.isDesignPreview)
                            if model.updater.available != nil {
                                Button("Download & open installer") { Task { await model.updater.downloadAndOpen() } }.buttonStyle(.borderedProminent).disabled(model.updater.busy || model.session.state.busy)
                            }
                            if model.updater.busy { ProgressView().controlSize(.small) }
                        }
                        Text("The installer’s checksum is verified before it opens. Updates keep your local history and saved connection.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your words stay your words.").font(.headline)
                    Text("FlowGpt preserves repetition, tone, and scripts. Currency expressions are normalized only when the amount and currency are identifiable. Related item phrases get circle bullets, procedural actions get numbers, and explicit currency amounts get symbols or currency codes. Only clear hesitation sounds are removed. The original returned transcript is always available in History.").foregroundStyle(.secondary)
                    Text("ChatGPT transcribes audio through a saved website session, which may expire. FlowGpt keeps the latest 100 transcripts on this Mac. It never sends a chat message. Multi-hour recordings are not supported.").foregroundStyle(.secondary)
                    Link("GitHub Releases", destination: URL(string: "https://github.com/rachitkothadia/FlowGPT/releases")!)
                }.font(.callout).fixedSize(horizontal: false, vertical: true)
            }.padding(30).frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
        }
    }

    private func permissionRow(_ title: String, detail: String, symbol: String, granted: Bool, allow: @escaping () -> Void) -> some View {
        let active = model.isDesignPreview || granted
        return HStack(spacing: 13) {
            Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(.secondary).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if active { FlowGptStatusBadge(title: "Allowed", active: true) }
            else { Button("Allow") { if !model.isDesignPreview { allow() } }.accessibilityLabel("Allow " + title) }
        }.accessibilityElement(children: .contain)
    }
}

private struct FlowGptCard<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: colorScheme == .dark ? .controlBackgroundColor : .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct FlowGptStatusBadge: View {
    let title: String
    let active: Bool
    @Environment(\.colorScheme) private var colorScheme
    private var statusColor: Color {
        colorScheme == .dark ? Color(red: 0.4, green: 0.82, blue: 0.64) : Color(red: 0.18, green: 0.49, blue: 0.36)
    }
    var body: some View {
        Label(title, systemImage: active ? "checkmark.circle.fill" : "circle")
            .font(.caption.weight(.medium)).foregroundStyle(active ? statusColor : .secondary)
    }
}

private struct FlowGptTranscriptView: View {
    let item: DictationResult
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "waveform").accessibilityHidden(true)
                Text(item.date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
            }.font(.caption).foregroundStyle(.secondary)
            if compact { Text(item.final).lineLimit(3).lineSpacing(4).frame(maxWidth: .infinity, alignment: .leading) }
            else { Text(item.final).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true) }
            if !compact {
                HStack {
                    Button("Copy text") { copy(item.final) }.controlSize(.small)
                    if item.raw != item.final { Button("Copy original") { copy(item.raw) }.controlSize(.small) }
                }
                if item.raw != item.final {
                    DisclosureGroup("Original transcript") { Text(item.raw).textSelection(.enabled).padding(.top, 8) }
                }
            }
        }
    }
    private func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
}

private struct FlowGptHistoryView: View {
    let history: [DictationResult]
    @State private var query = ""
    @Environment(\.colorScheme) private var colorScheme
    private var matches: [DictationResult] { query.isEmpty ? history : history.filter { $0.final.localizedStandardContains(query) } }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your words, saved.").font(.system(size: 27, weight: .semibold)).tracking(-0.5)
                    Text("\(history.count) dictations on this Mac").foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(.horizontal, 30).padding(.top, 26).padding(.bottom, 22)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search your dictations", text: $query).textFieldStyle(.plain).accessibilityLabel("Search your dictations")
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear search") }
            }.padding(11).background(Color(nsColor: colorScheme == .dark ? .controlBackgroundColor : .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10)).padding(.horizontal, 30).padding(.bottom, 20)
            if matches.isEmpty {
                Spacer()
                FlowGptEmptyView(symbol: "clock", title: query.isEmpty ? "A fresh start" : "No matching dictations", detail: query.isEmpty ? "Finish a dictation and you’ll find it here." : "Try a different word or clear your search.").padding(30)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(matches) { item in FlowGptCard { FlowGptTranscriptView(item: item) } }
                    }.padding(.horizontal, 30).padding(.bottom, 30)
                }
            }
        }
    }
}

private struct FlowGptEmptyView: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 30, weight: .light)).foregroundStyle(.tertiary).padding(.bottom, 4)
            Text(title).font(.headline)
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 24)
    }
}

struct FlowGptRecordingStrip: View {
    let state: SessionState
    var audioLevel: Double = 0
    let finish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        HStack(spacing: 10) {
            if state == .recording {
                Button(action: finish) { Image(systemName: "mic.fill").font(.system(size: 14)).frame(width: 24, height: 26).contentShape(Rectangle()) }
                    .buttonStyle(.plain).accessibilityLabel("Finish dictation")
            } else { ProgressView().controlSize(.small).frame(width: 24, height: 28).accessibilityLabel("Processing dictation") }
            HStack(spacing: 3) {
                ForEach(0..<7, id: \.self) { index in
                    let weight = [0.35, 0.65, 0.9, 1.0, 0.85, 0.55, 0.3][index]
                    Capsule().fill(state == .recording ? Color.white : Color.white.opacity(0.3))
                        .frame(width: 2, height: state == .recording ? 3 + 19 * min(1, max(0, audioLevel)) * weight : 3)
                }
            }.frame(width: 34, height: 24)
                .animation(reduceMotion ? nil : .linear(duration: 0.08), value: audioLevel)
                .accessibilityHidden(true)
        }
        .foregroundStyle(.white).frame(width: 104, height: 32)
        .modifier(FlowGptGlass(reduceTransparency: reduceTransparency))
        .environment(\.colorScheme, .dark).padding(6)
    }
}

private struct FlowGptGlass: ViewModifier {
    let reduceTransparency: Bool
    func body(content: Content) -> some View {
        if reduceTransparency { content.background(Color.black, in: Capsule()) }
        else if #available(macOS 26.0, *) { content.glassEffect(.regular.tint(.black.opacity(0.6)).interactive(), in: Capsule()) }
        else { content.background(.ultraThinMaterial, in: Capsule()) }
    }
}
