import AppKit
import ApplicationServices
import FlowCore

/// Explicit developer fixture. Only a deliberately created empty Office
/// document with the exact fixture title is eligible; never opens user files.
@MainActor enum OfficeInsertionChecks {
    static func run() {
        Task { @MainActor in
            var checks: [String: Bool] = [:]
            var contract: [String: String] = [:]
            let titleIndex = CommandLine.arguments.firstIndex(of: "--fixture-title")
            let title = titleIndex.flatMap { index in index + 1 < CommandLine.arguments.count ? CommandLine.arguments[index + 1] : nil }
                ?? (CommandLine.arguments.contains("--powerpoint") ? "Presentation1" : "Document1")
            let bundle = CommandLine.arguments.contains("--powerpoint") ? "com.microsoft.Powerpoint" : "com.microsoft.Word"
            func attr(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
                var value: CFTypeRef?
                guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
                return value
            }
            func ax(_ value: CFTypeRef?) -> AXUIElement? {
                guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
                return unsafeDowncast(value, to: AXUIElement.self)
            }
            do {
                guard AXIsProcessTrusted(), let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else { throw FlowError.accessibility }
                let application = AXUIElementCreateApplication(app.processIdentifier)
                if CommandLine.arguments.contains("--enhance") {
                    let status = AXUIElementSetAttributeValue(application, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
                    contract["enhancementStatus"] = String(status.rawValue)
                }
                guard let window = ax(attr(application, kAXFocusedWindowAttribute)), attr(window, kAXTitleAttribute) as? String == title else { throw FlowError.targetChanged }
                app.activate()
                try await Task.sleep(for: .milliseconds(300))
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
                      let field = ax(attr(application, kAXFocusedUIElementAttribute)) else { throw FlowError.targetChanged }
                let value = attr(field, kAXValueAttribute) as? String
                guard value == nil || value?.allSatisfy(\.isWhitespace) == true else { throw FlowError.targetChanged }
                for name in [kAXRoleAttribute, kAXSubroleAttribute, kAXEnabledAttribute, "AXEditable", "AXReadOnly", kAXIdentifierAttribute] {
                    contract[name] = attr(field, name).map { String(describing: $0) } ?? "unavailable"
                }
                var names: CFArray?
                AXUIElementCopyParameterizedAttributeNames(field, &names)
                contract["parameterizedAttributes"] = String(describing: names as? [String] ?? [])
                contract["hasRange"] = String(attr(field, kAXSelectedTextRangeAttribute) != nil)
                var attributes: CFArray?
                AXUIElementCopyAttributeNames(field, &attributes)
                contract["attributeNames"] = String(describing: attributes as? [String] ?? [])
                contract["hasTextMarkerRange"] = String(attr(field, "AXSelectedTextMarkerRange") != nil)
                contract["hasInsertionLine"] = String(attr(field, "AXInsertionPointLineNumber") != nil)
                func shape(_ node: AXUIElement, depth: Int) -> [String] {
                    guard depth < 4 else { return [] }
                    var children = attr(node, kAXChildrenAttribute) as? [AXUIElement] ?? []
                    if children.isEmpty { children = attr(node, "AXContents") as? [AXUIElement] ?? [] }
                    return children.prefix(12).flatMap { child -> [String] in
                        var range = CFRange(location: -9, length: -9)
                        if let raw = attr(child, kAXSelectedTextRangeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() { _ = AXValueGetValue(unsafeDowncast(raw, to: AXValue.self), .cfRange, &range) }
                        var parameters: CFArray?
                        AXUIElementCopyParameterizedAttributeNames(child, &parameters)
                        return [String(repeating: ".", count: depth) + (attr(child, kAXRoleAttribute) as? String ?? "unknown") + " selected=\(attr(child, kAXSelectedAttribute) as? Bool ?? false) focused=\(attr(child, kAXFocusedAttribute) as? Bool ?? false) range=\(range.location):\(range.length) params=\(parameters as? [String] ?? [])"] + shape(child, depth: depth + 1)
                    }
                }
                contract["childCapabilities"] = shape(field, depth: 0).joined(separator: ", ")
                if CommandLine.arguments.contains("--inspect-only") {
                    checks["contractCapturedWithoutInsertion"] = true
                } else {
                let board = NativeClipboard(), original = try board.snapshot()
                let service = InsertionService(); service.collectDiagnostics = true; service.captureTarget()
                contract["target"] = service.diagnosticTarget()
                let started = ProcessInfo.processInfo.systemUptime
                let outcome = try await service.insert("FlowGpt test: Hello, नमस्ते, नमस्कार.", preserveClipboard: true)
                let latency = (ProcessInfo.processInfo.systemUptime - started) * 1_000
                contract["insertionMilliseconds"] = String(format: "%.1f", latency)
                for (name, duration) in service.insertionDiagnostics { contract["timing." + name] = String(format: "%.2f", duration) }
                checks["insertionReturnsBelow250Milliseconds"] = latency < 250
                contract["adapterOutcome"] = outcome == .confirmed ? "confirmed" : "attempted"
                await InsertionService.waitForPendingPaste()
                checks["allClipboardFormatsRestored"] = try board.snapshot() == original
                func containsPayload(_ node: AXUIElement, depth: Int) -> Bool {
                    guard depth < 6 else { return false }
                    if (attr(node, kAXValueAttribute) as? String)?.contains("FlowGpt test: Hello, नमस्ते, नमस्कार.") == true { return true }
                    return (attr(node, kAXChildrenAttribute) as? [AXUIElement] ?? []).prefix(12).contains { containsPayload($0, depth: depth + 1) }
                }
                checks["focusedEditorContainsMixedText"] = containsPayload(field, depth: 0)
                }
            } catch { contract["failure"] = error.localizedDescription; checks["productionAdapterDelivered"] = false }
            let report: [String: Any] = ["type": "Disposable Office editor production insertion fixture", "checks": checks, "contract": contract, "passed": checks.values.allSatisfy { $0 }]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: "/tmp/flowgpt-office-insertion-check.json"), options: .atomic)
            }
            NSApp.terminate(nil)
        }
    }
}
