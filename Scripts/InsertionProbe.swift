// QA helper: exercises the actual production insertion adapter; never bundled.
import AppKit
import FlowCore

@main struct InsertionProbe {
    @MainActor static func main() async {
        let service = InsertionService()
        service.useAccessibility = !CommandLine.arguments.contains("--paste")
        let board = NativeClipboard()
        service.captureTarget()
        do {
            let original = try board.snapshot()
            if CommandLine.arguments.contains("--wait") { try await Task.sleep(for: .seconds(5)) }
            let result = try await service.insert("Flow insertion verification.", preserveClipboard: true)
            await InsertionService.waitForPendingPaste()
            let restored = try board.snapshot() == original
            print("Outcome: \(result == .confirmed ? "confirmed" : "attempted")")
            print("All clipboard formats preserved: \(restored)")
        } catch { print("Insertion refused: \((error as? FlowError ?? .insertion).localizedDescription)"); exit(1) }
    }
}
