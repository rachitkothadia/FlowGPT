import AppKit
import ApplicationServices
import FlowCore

@MainActor final class NativeClipboard: ClipboardAccess {
    typealias Snapshot = [[NSPasteboard.PasteboardType: Data]]
    private let board: NSPasteboard
    init(board: NSPasteboard = .general) { self.board = board }
    var revision: Int { board.changeCount }
    func snapshot() throws -> Snapshot {
        var bytes = 0
        return try (board.pasteboardItems ?? []).map { item in
            var result: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else { throw FlowError.insertion }
                guard data.count <= 32 * 1_024 * 1_024 - bytes else { throw FlowError.clipboard }
                bytes += data.count
                result[type] = data
            }
            return result
        }
    }
    func write(_ text: String) throws -> Int {
        board.clearContents()
        guard board.setString(text, forType: .string) else { throw FlowError.insertion }
        return board.changeCount
    }
    func restore(_ snapshot: Snapshot) {
        let items = snapshot.map { values in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        }
        board.clearContents()
        if !items.isEmpty { board.writeObjects(items) }
    }
}

@MainActor final class InsertionService: TextInsertion {
    private static var pasteInFlight = false
    private static var restoration: Task<Void, Never>?
    static func waitForPendingPaste() async { await restoration?.value }
    var useAccessibility = true
    // Explicit QA only: durations/counts contain attribute names, never content.
    var collectDiagnostics = false
    private(set) var insertionDiagnostics: [String: Double] = [:]
    private func timed<T>(_ name: String, _ operation: () throws -> T) rethrows -> T {
        guard collectDiagnostics else { return try operation() }
        let started = ProcessInfo.processInfo.systemUptime
        defer {
            insertionDiagnostics[name + ".milliseconds", default: 0] += (ProcessInfo.processInfo.systemUptime - started) * 1_000
            insertionDiagnostics[name + ".calls", default: 0] += 1
        }
        return try operation()
    }
    private var pid: pid_t?
    private var element: AXUIElement?
    private var window: AXUIElement?
    private var identifier: String?
    private var document: String?
    private var resolvedProxy: AXUIElement?
    private var resolvedEditor: AXUIElement?
    private var sent = false
    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard timed("attribute." + name, { AXUIElementCopyAttributeValue(element, name as CFString, &value) }) == .success else { return nil }
        return value
    }
    private func ax(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }
    private func ancestors(_ element: AXUIElement) -> [AXUIElement] {
        var nodes = [element]
        for _ in 0..<24 {
            guard let parent = ax(attribute(nodes.last!, kAXParentAttribute)),
                  !nodes.contains(where: { CFEqual($0, parent) }) else { break }
            nodes.append(parent)
        }
        return nodes
    }
    private func writable(_ element: AXUIElement, _ name: String) -> Bool {
        var value: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, name as CFString, &value) == .success && value.boolValue
    }
    private func editable(_ element: AXUIElement) -> Bool {
        let role = attribute(element, kAXRoleAttribute) as? String ?? ""
        var rawAttributes: CFArray?
        guard AXUIElementCopyAttributeNames(element, &rawAttributes) == .success else { return false }
        let attributes = Set(rawAttributes as? [String] ?? [])
        // Office returns default values for some unadvertised attributes.
        // A default AXEnabled=false is not evidence that the editor is disabled.
        func declaredBool(_ name: String) -> Bool? {
            attributes.contains(name) ? attribute(element, name) as? Bool : nil
        }
        var names: CFArray?
        AXUIElementCopyParameterizedAttributeNames(element, &names)
        let supported = names as? [String] ?? []
        let rangedText = supported.contains(kAXStringForRangeParameterizedAttribute)
            || supported.contains(kAXAttributedStringForRangeParameterizedAttribute)
            || supported.contains("AXStringForTextMarkerRange")
        return InsertionSafety.editableCapability(explicitEditable: declaredBool("AXEditable"),
            explicitReadOnly: declaredBool("AXReadOnly"),
            enabled: declaredBool(kAXEnabledAttribute),
            standardTextRole: [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role),
            writableValue: writable(element, kAXValueAttribute), writableSelectedText: writable(element, kAXSelectedTextAttribute),
            hasSelectedRange: attribute(element, kAXSelectedTextRangeAttribute) != nil || attribute(element, "AXSelectedTextMarkerRange") != nil,
            supportsTextRange: rangedText, supportsRangeReplacement: supported.contains("AXReplaceRangeWithText"))
    }
    private struct FocusedTarget {
        let raw: AXUIElement
        let editor: AXUIElement
    }
    private func focused(_ pid: pid_t) -> FocusedTarget? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        guard let raw = ax(attribute(app, kAXFocusedUIElementAttribute)) else { return nil }
        // Never climb out of a secure or read-only focused field into a parent editor.
        if attribute(raw, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole
            || [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(attribute(raw, kAXRoleAttribute) as? String ?? "") { return FocusedTarget(raw: raw, editor: raw) }
        // Contenteditable frameworks sometimes expose a focused child inside the editor.
        if let editor = ancestors(raw).first(where: editable) { return FocusedTarget(raw: raw, editor: editor) }
        // Native editors sometimes report their enclosing scroll view as focus.
        // Resolve only one actual editor, and only when the proxy publishes a
        // text insertion line. A canvas/shape proxy without caret evidence stays
        // blocked even if it advertises a generic replacement operation.
        let proxyRole = attribute(raw, kAXRoleAttribute) as? String ?? ""
        if [kAXScrollAreaRole, "AXLayoutArea"].contains(proxyRole),
           attribute(raw, "AXInsertionPointLineNumber") != nil,
           attribute(raw, "AXReadOnly") as? Bool != true {
            if let proxy = resolvedProxy, let editor = resolvedEditor,
               CFEqual(proxy, raw), ancestors(editor).contains(where: { CFEqual($0, raw) }), editable(editor) { return FocusedTarget(raw: raw, editor: editor) }
            var candidates: [AXUIElement] = []
            func inspect(_ node: AXUIElement, depth: Int) {
                guard depth < 5, candidates.count < 2 else { return }
                for child in (attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? []).prefix(12) {
                    if editable(child) { candidates.append(child) } else { inspect(child, depth: depth + 1) }
                    if candidates.count > 1 { break }
                }
            }
            inspect(raw, depth: 0)
            if candidates.count == 1 { resolvedProxy = raw; resolvedEditor = candidates[0]; return FocusedTarget(raw: raw, editor: candidates[0]) }
        }
        return FocusedTarget(raw: raw, editor: raw)
    }
    private func fieldIdentifier(_ element: AXUIElement) -> String? {
        (attribute(element, "AXDOMIdentifier") as? String)
            ?? (attribute(element, kAXIdentifierAttribute) as? String)
    }
    private func documentURL(in nodes: [AXUIElement]) -> String? {
        for node in nodes {
            let value = attribute(node, kAXURLAttribute)
            if let url = value as? URL { return url.absoluteString }
            if let url = value as? String { return url }
            if let document = attribute(node, kAXDocumentAttribute) as? String { return document }
        }
        return nil
    }
    private func windowForElement(_ element: AXUIElement, ancestors nodes: [AXUIElement]) -> AXUIElement? {
        ax(attribute(element, kAXWindowAttribute))
            ?? nodes.first { attribute($0, kAXRoleAttribute) as? String == kAXWindowRole }
    }
    func captureTarget() {
        resolvedProxy = nil; resolvedEditor = nil
        sent = false; pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if let pid, pid != ProcessInfo.processInfo.processIdentifier,
           focused(pid).map({ !editable($0.editor) }) ?? true {
            // Electron exposes its editable tree through this documented app
            // attribute. This does not request or change a macOS privacy grant.
            AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }
        element = pid.flatMap { focused($0)?.editor }
        let nodes = element.map { ancestors($0) } ?? []
        window = element.flatMap { windowForElement($0, ancestors: nodes) }
        identifier = element.flatMap { fieldIdentifier($0) }
        document = documentURL(in: nodes)
    }
    func reset() { pid = nil; element = nil; window = nil; identifier = nil; document = nil; sent = false; resolvedProxy = nil; resolvedEditor = nil }
    func diagnosticTarget() -> String {
        let app = pid.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier } ?? "unknown"
        guard let element else { return "App=\(app), no focused accessibility element" }
        return "App=\(app), role=\(attribute(element, kAXRoleAttribute) as? String ?? "unknown"), editable=\(editable(element))"
    }
    private struct ValidatedTarget {
        let element: AXUIElement
        let ancestors: [AXUIElement]
        let rawFocus: AXUIElement
        let window: AXUIElement?
    }
    private func validateTarget() throws -> ValidatedTarget {
        guard AXIsProcessTrusted() else { throw FlowError.accessibility }
        guard let pid, pid != ProcessInfo.processInfo.processIdentifier,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let original = element, let focus = focused(pid) else { throw FlowError.targetChanged }
        let current = focus.editor
        // Share one ancestry snapshot only inside this synchronous validation.
        // The pre-paste validation always collects a fresh snapshot.
        let nodes = ancestors(current)
        let currentWindow = windowForElement(current, ancestors: nodes)
        let sameWindow = window.flatMap { old in currentWindow.map { CFEqual(old, $0) } } ?? CFEqual(original, current)
        let sameElement = CFEqual(original, current)
        guard InsertionSafety.sameTarget(sameElement: sameElement, sameWindow: sameWindow,
            originalIdentifier: identifier, currentIdentifier: sameElement ? nil : fieldIdentifier(current),
            originalDocument: document, currentDocument: document == nil ? nil : documentURL(in: nodes)) else { throw FlowError.targetChanged }
        guard !nodes.contains(where: { attribute($0, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole }) else { throw FlowError.secureField }
        guard !nodes.contains(where: { attribute($0, "AXReadOnly") as? Bool == true }) else { throw FlowError.insertion }
        guard editable(current) else { throw FlowError.insertion }
        return ValidatedTarget(element: current, ancestors: nodes, rawFocus: focus.raw, window: currentWindow)
    }
    private func requireCurrentFocus(_ target: ValidatedTarget) throws {
        guard let pid else { throw FlowError.targetChanged }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        // Read only the identities already validated, without another tree walk.
        // Office may focus a proxy, so compare its raw focus as well as window.
        // Last check after all cross-process reads: a switch during an AX RPC
        // must not send a global paste or a selected-text write to stale focus.
        guard InsertionSafety.canWriteToCurrentFocus(sameWindow: {
            guard let window = target.window else { return true }
            guard let focusedWindow = ax(attribute(app, kAXFocusedWindowAttribute)) else { return false }
            return CFEqual(window, focusedWindow)
        }, sameFocusedElement: {
            guard let focusedElement = ax(attribute(app, kAXFocusedUIElementAttribute)) else { return false }
            return CFEqual(target.rawFocus, focusedElement)
        }, sameForegroundProcess: {
            NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
        }) else { throw FlowError.targetChanged }
    }
    private func expectedValue(_ current: AXUIElement, text: String) -> String? {
        guard let before = attribute(current, kAXValueAttribute) as? String,
              let rangeValue = attribute(current, kAXSelectedTextRangeAttribute), CFGetTypeID(rangeValue) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(unsafeDowncast(rangeValue, to: AXValue.self), .cfRange, &range), range.location >= 0, range.length >= 0,
              range.location <= (before as NSString).length,
              range.length <= (before as NSString).length - range.location else { return nil }
        return (before as NSString).replacingCharacters(in: NSRange(location: range.location, length: range.length), with: text)
    }
    func insert(_ text: String, preserveClipboard: Bool) async throws -> InsertionOutcome {
        insertionDiagnostics = [:]
        try Task.checkCancellation(); guard !sent else { throw FlowError.insertion }
        let text = try TextValidation.validate(text)
        let validated = try timed("stage.validation", { try validateTarget() })
        let current = validated.element
        let web = timed("stage.webAncestry", { validated.ancestors.contains { attribute($0, kAXRoleAttribute) as? String == "AXWebArea" } })
        if useAccessibility, !web, writable(current, kAXSelectedTextAttribute),
           timed("stage.expectedValue", { expectedValue(current, text: text) }) != nil {
            try timed("stage.finalWriteFocus", { try requireCurrentFocus(validated) })
            if AXUIElementSetAttributeValue(current, kAXSelectedTextAttribute as CFString, text as CFString) == .success {
                sent = true
                // The provider acknowledged the write. A synchronous full-value
                // read can block on native rich editors, so don't delay delivery
                // or claim confirmation without a separate observed result.
                return .attempted
            }
        }
        // One native paste handles DOM/Electron editors, IMEs and long multilingual
        // strings without replaying uncertain Unicode events and duplicating text.
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { throw FlowError.insertion }
        down.flags = .maskCommand; up.flags = .maskCommand
        guard !Self.pasteInFlight else { throw FlowError.insertion }
        Self.pasteInFlight = true
        var handedOff = false
        defer { if !handedOff { Self.pasteInFlight = false } }
        let lease = try timed("stage.clipboard", { try ClipboardLease(NativeClipboard(), text: text) })
        defer { if !handedOff { lease.restore() } }
        try Task.checkCancellation()
        let pasteTarget = try timed("stage.prePasteValidation", { try validateTarget() })
        try timed("stage.finalPasteFocus", { try requireCurrentFocus(pasteTarget) })
        sent = true
        // Follow the native keyboard event route. Process-directed events can
        // bypass the foreground rich editor's responder/input handling.
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        // Keep the payload alive separately from the visible insertion state.
        // This task is independent of the dictation task's cancellation. Quit
        // awaits it, and changeCount ownership still protects a newer user copy.
        Self.restoration = Task { @MainActor in
            await Task.detached { try? await Task<Never, Never>.sleep(for: .milliseconds(700)) }.value
            lease.restore()
            Self.pasteInFlight = false
            Self.restoration = nil
        }
        handedOff = true
        // Dispatch is a handoff, not proof that an external app consumed text.
        // Never block the dictation result on its Accessibility value provider,
        // and never replay an uncertain paste. Explicit QA observes delivery.
        return .attempted
    }
}
