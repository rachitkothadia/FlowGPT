import AppKit
import ApplicationServices
import FlowCore

@MainActor final class NativeClipboard: ClipboardAccess {
    typealias Snapshot = [[NSPasteboard.PasteboardType: Data]]
    private let board: NSPasteboard
    init(board: NSPasteboard = .general) { self.board = board }
    var revision: Int { board.changeCount }
    func snapshot() throws -> Snapshot {
        try (board.pasteboardItems ?? []).map { item in
            var result: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else { throw FlowError.insertion }
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
    var useAccessibility = true
    private var pid: pid_t?
    private var element: AXUIElement?
    private var window: AXUIElement?
    private var identifier: String?
    private var document: String?
    private var sent = false
    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
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
        if attribute(element, "AXEditable") as? Bool == false || attribute(element, "AXReadOnly") as? Bool == true { return false }
        let role = attribute(element, kAXRoleAttribute) as? String ?? ""
        return ([kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role)
                && writable(element, kAXValueAttribute))
            || attribute(element, "AXEditable") as? Bool == true
            || writable(element, kAXSelectedTextAttribute)
    }
    private func focused(_ pid: pid_t) -> AXUIElement? {
        guard let raw = ax(attribute(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute)) else { return nil }
        // Never climb out of a secure or read-only focused field into a parent editor.
        if attribute(raw, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole
            || [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(attribute(raw, kAXRoleAttribute) as? String ?? "") { return raw }
        // Contenteditable frameworks sometimes expose a focused child inside the editor.
        return ancestors(raw).first(where: editable) ?? raw
    }
    private func fieldIdentifier(_ element: AXUIElement) -> String? {
        (attribute(element, "AXDOMIdentifier") as? String)
            ?? (attribute(element, kAXIdentifierAttribute) as? String)
    }
    private func documentURL(_ element: AXUIElement) -> String? {
        for node in ancestors(element) {
            if let url = attribute(node, kAXURLAttribute) as? URL { return url.absoluteString }
            if let url = attribute(node, kAXURLAttribute) as? String { return url }
        }
        return nil
    }
    func captureTarget() {
        sent = false; pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if let pid, pid != ProcessInfo.processInfo.processIdentifier,
           focused(pid).map({ !editable($0) }) ?? true {
            // Electron exposes its editable tree through this documented app
            // attribute. This does not request or change a macOS privacy grant.
            AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }
        element = pid.flatMap { focused($0) }
        window = element.flatMap { ax(attribute($0, kAXWindowAttribute)) }
        identifier = element.flatMap { fieldIdentifier($0) }
        document = element.flatMap { documentURL($0) }
    }
    func reset() { pid = nil; element = nil; window = nil; identifier = nil; document = nil; sent = false }
    func diagnosticTarget() -> String {
        let app = pid.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier } ?? "unknown"
        guard let element else { return "App=\(app), no focused accessibility element" }
        return "App=\(app), role=\(attribute(element, kAXRoleAttribute) as? String ?? "unknown"), editable=\(editable(element))"
    }
    private func validateTarget() throws -> AXUIElement {
        guard AXIsProcessTrusted() else { throw FlowError.accessibility }
        guard let pid, pid != ProcessInfo.processInfo.processIdentifier,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let original = element, let current = focused(pid) else { throw FlowError.targetChanged }
        let currentWindow = ax(attribute(current, kAXWindowAttribute))
        let sameWindow = window.flatMap { old in currentWindow.map { CFEqual(old, $0) } } ?? CFEqual(original, current)
        guard InsertionSafety.sameTarget(sameElement: CFEqual(original, current), sameWindow: sameWindow,
            originalIdentifier: identifier, currentIdentifier: fieldIdentifier(current),
            originalDocument: document, currentDocument: documentURL(current)) else { throw FlowError.targetChanged }
        guard !ancestors(current).contains(where: { attribute($0, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole }) else { throw FlowError.secureField }
        guard editable(current), attribute(current, kAXEnabledAttribute) as? Bool != false else { throw FlowError.insertion }
        return current
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
        try Task.checkCancellation(); guard !sent else { throw FlowError.insertion }
        let text = try TextValidation.validate(text)
        let current = try validateTarget()
        let expected = expectedValue(current, text: text)
        let web = ancestors(current).contains { attribute($0, kAXRoleAttribute) as? String == "AXWebArea" }
        if useAccessibility, expected != nil, !web, writable(current, kAXSelectedTextAttribute),
           AXUIElementSetAttributeValue(current, kAXSelectedTextAttribute as CFString, text as CFString) == .success {
            sent = true
            return attribute(current, kAXValueAttribute) as? String == expected ? .confirmed : .attempted
        }
        // One native paste handles DOM/Electron editors, IMEs and long multilingual
        // strings without replaying uncertain Unicode events and duplicating text.
        guard let pid, let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { throw FlowError.insertion }
        down.flags = .maskCommand; up.flags = .maskCommand
        guard !Self.pasteInFlight else { throw FlowError.insertion }
        Self.pasteInFlight = true
        defer { Self.pasteInFlight = false }
        let lease = try ClipboardLease(NativeClipboard(), text: text)
        defer { lease.restore() }
        try Task.checkCancellation(); _ = try validateTarget()
        sent = true
        down.postToPid(pid); up.postToPid(pid)
        // A canceled session must still leave the payload available long enough for
        // the editor to consume it, then restore it. No replay after event delivery.
        for tick in 0..<15 {
            try? await Task<Never, Never>.sleep(for: .milliseconds(40))
            if let expected, let focused = try? validateTarget(), attribute(focused, kAXValueAttribute) as? String == expected { return .confirmed }
            if Task.isCancelled { await Self.drainPaste(); return .attempted }
            if tick == 14 { return .attempted }
        }
        return .attempted
    }
    private static func drainPaste() async {
        // Detached wait is not inherited from a canceled dictation task.
        await Task.detached { try? await Task<Never, Never>.sleep(for: .milliseconds(600)) }.value
    }
}
