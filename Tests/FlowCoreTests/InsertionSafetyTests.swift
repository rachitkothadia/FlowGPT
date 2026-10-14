import Foundation
import Testing
@testable import FlowCore

@MainActor private final class TestClipboard: ClipboardAccess {
    var revision = 1
    var contents: [[String: Data]] = []
    var failSnapshot = false
    var failWrite = false
    var copyDuringSnapshot = false
    var restores = 0
    func snapshot() throws -> [[String: Data]] {
        if failSnapshot { throw FlowError.insertion }
        if copyDuringSnapshot { revision += 1 }
        return contents
    }
    func write(_ text: String) throws -> Int {
        revision += 1
        contents = [["text": Data(text.utf8)]]
        if failWrite { throw FlowError.insertion }
        return revision
    }
    func restore(_ snapshot: [[String: Data]]) { contents = snapshot; revision += 1; restores += 1 }
}

@Suite struct InsertionSafetyTests {
    @Test func appSwitchDuringProviderReadsRefusesFinalWrite() {
        for switchDuringWindowRead in [false, true] {
            var foregroundIsTarget = true
            let allowed = InsertionSafety.canWriteToCurrentFocus(sameWindow: {
                if switchDuringWindowRead { foregroundIsTarget = false }
                return true
            }, sameFocusedElement: {
                if !switchDuringWindowRead { foregroundIsTarget = false }
                return true
            }, sameForegroundProcess: { foregroundIsTarget })
            #expect(!allowed)
        }
    }
    @Test func sameProcessWithChangedWindowOrFieldRefusesFinalWrite() {
        #expect(!InsertionSafety.canWriteToCurrentFocus(sameWindow: { false }, sameFocusedElement: { true }, sameForegroundProcess: { true }))
        #expect(!InsertionSafety.canWriteToCurrentFocus(sameWindow: { true }, sameFocusedElement: { false }, sameForegroundProcess: { true }))
        #expect(InsertionSafety.canWriteToCurrentFocus(sameWindow: { true }, sameFocusedElement: { true }, sameForegroundProcess: { true }))
    }
    @Test func originalFieldRequiresSameWindow() {
        #expect(InsertionSafety.sameTarget(sameElement: true, sameWindow: true, originalIdentifier: nil, currentIdentifier: nil, originalDocument: nil, currentDocument: nil))
        #expect(!InsertionSafety.sameTarget(sameElement: true, sameWindow: false, originalIdentifier: nil, currentIdentifier: nil, originalDocument: nil, currentDocument: nil))
        #expect(!InsertionSafety.sameTarget(sameElement: true, sameWindow: true, originalIdentifier: nil, currentIdentifier: nil, originalDocument: "old", currentDocument: "new"))
    }
    @Test func recreatedDOMFieldMustRetainIdentityAndDocument() {
        for sameWindow in [false, true] {
            for id in [nil, "", "other", "composer"] as [String?] {
                for document in [nil, "", "https://other.test", "https://editor.test"] as [String?] {
                    #expect(InsertionSafety.sameTarget(sameElement: false, sameWindow: sameWindow,
                        originalIdentifier: "composer", currentIdentifier: id,
                        originalDocument: "https://editor.test", currentDocument: document)
                        == (sameWindow && id == "composer" && document == "https://editor.test"))
                }
            }
        }
    }
    @Test @MainActor func allFormatsAndMultipleItemsRestored() throws {
        let board = TestClipboard()
        let original = [["text": Data("previous".utf8), "rtf": Data([0, 1, 2])], ["image": Data([3, 4, 5])]]
        board.contents = original
        let lease = try ClipboardLease(board, text: "नमस्ते 🎤\nSwift C++")
        #expect(board.contents != original)
        lease.restore(); lease.restore()
        #expect(board.contents == original)
        #expect(board.restores == 1)
    }
    @Test @MainActor func emptyClipboardRestored() throws {
        let board = TestClipboard(); let lease = try ClipboardLease(board, text: "hello")
        lease.restore(); #expect(board.contents.isEmpty)
    }
    @Test @MainActor func concurrentUserCopyWins() throws {
        let board = TestClipboard(); let lease = try ClipboardLease(board, text: "dictation")
        _ = try board.write("user's new copy")
        let newCopy = board.contents
        lease.restore(); #expect(board.contents == newCopy); #expect(board.restores == 0)
    }
    @Test @MainActor func unavailablePromisedDataDoesNotMutate() {
        let board = TestClipboard(); board.failSnapshot = true
        #expect(throws: FlowError.self) { try ClipboardLease(board, text: "hello") }
        #expect(board.revision == 1 && board.restores == 0)
    }
    @Test @MainActor func copyDuringSnapshotStopsWrite() {
        let board = TestClipboard(); board.copyDuringSnapshot = true
        #expect(throws: FlowError.self) { try ClipboardLease(board, text: "hello") }
        #expect(board.contents.isEmpty && board.restores == 0)
    }
    @Test @MainActor func failedWriteRestoresOriginal() {
        let board = TestClipboard(); board.contents = [["image": Data([1, 2])]]; board.failWrite = true
        let original = board.contents
        #expect(throws: FlowError.self) { try ClipboardLease(board, text: "hello") }
        #expect(board.contents == original && board.restores == 1)
    }
}
