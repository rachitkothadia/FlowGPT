import Foundation

/// A recreated web field is accepted only when its window, document and stable
/// identifier still match. An arbitrary newly focused field is never a fallback.
public enum InsertionSafety {
    public static func sameTarget(sameElement: Bool, sameWindow: Bool,
                                  originalIdentifier: String?, currentIdentifier: String?,
                                  originalDocument: String?, currentDocument: String?) -> Bool {
        guard sameWindow else { return false }
        if let originalDocument, originalDocument != currentDocument { return false }
        if sameElement { return true }
        guard let originalIdentifier, !originalIdentifier.isEmpty,
              originalIdentifier == currentIdentifier,
              let originalDocument, !originalDocument.isEmpty,
              originalDocument == currentDocument else { return false }
        return true
    }
}

@MainActor public protocol ClipboardAccess: AnyObject {
    associatedtype Snapshot
    var revision: Int { get }
    func snapshot() throws -> Snapshot
    /// Returns the revision belonging to the temporary text payload.
    func write(_ text: String) throws -> Int
    func restore(_ snapshot: Snapshot)
}

/// Owns one temporary payload. A copy made by the user while insertion is running
/// takes precedence over restoration. No clipboard data is persisted or logged.
@MainActor public final class ClipboardLease<Clipboard: ClipboardAccess> {
    private let clipboard: Clipboard
    private let original: Clipboard.Snapshot
    private var ownedRevision: Int?
    public init(_ clipboard: Clipboard, text: String) throws {
        self.clipboard = clipboard
        let revision = clipboard.revision
        original = try clipboard.snapshot()
        guard clipboard.revision == revision else { throw FlowError.insertion }
        do { ownedRevision = try clipboard.write(text) }
        catch {
            // write is synchronous on the main actor: any mutation here belongs
            // to this failed write, rather than a later user copy.
            if clipboard.revision != revision { clipboard.restore(original) }
            throw error
        }
    }
    public func restore() {
        guard let ownedRevision else { return }
        self.ownedRevision = nil
        if clipboard.revision == ownedRevision { clipboard.restore(original) }
    }
}
