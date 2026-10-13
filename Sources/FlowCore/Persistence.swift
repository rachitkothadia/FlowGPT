import Foundation

public struct APIKeyStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public static func validated(_ value: String) throws -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count < 512,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw FlowError.missingKey }
        return value
    }
    public func load() throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else { return "" }
        do {
            let data = try Data(contentsOf: url)
            guard data.count < 2048, let value = String(data: data, encoding: .utf8) else { throw FlowError.storage }
            return try Self.validated(value)
        } catch { throw FlowError.storage }
    }
    public func save(_ value: String) throws {
        let value = try Self.validated(value)
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            // Atomic replacement uses a private temporary file from the first write.
            let temporary = url.deletingLastPathComponent().appendingPathComponent(".api-key-" + UUID().uuidString)
            defer { try? fm.removeItem(at: temporary) }
            guard fm.createFile(atPath: temporary.path, contents: Data(value.utf8), attributes: [.posixPermissions: 0o600]) else { throw FlowError.storage }
            if fm.fileExists(atPath: url.path) { _ = try fm.replaceItemAt(url, withItemAt: temporary) }
            else { try fm.moveItem(at: temporary, to: url) }
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { throw FlowError.storage }
    }
    public func delete() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do { try FileManager.default.removeItem(at: url) } catch { throw FlowError.storage }
    }
}

public enum PreferenceStore {
    public static func load(from defaults: UserDefaults) throws -> Preferences {
        guard let data = defaults.data(forKey: "preferences.v1") else { return Preferences() }
        guard var value = try? JSONDecoder().decode(Preferences.self, from: data) else { throw FlowError.storage }
        value.sanitize(); return value
    }
    public static func save(_ preferences: Preferences, to defaults: UserDefaults) throws {
        var value = preferences; value.sanitize()
        defaults.set(try JSONEncoder().encode(value), forKey: "preferences.v1")
    }
}
public actor HistoryStore {
    private let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> [DictationResult] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        struct Envelope: Codable { let version: Int; let entries: [DictationResult] }
        guard let data = try? Data(contentsOf: url), data.count <= 20_000_000,
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data), envelope.version == 1 else { throw FlowError.storage }
        return Array(envelope.entries.prefix(100))
    }
    public func save(_ entries: [DictationResult]) throws {
        struct Envelope: Codable { let version: Int; let entries: [DictationResult] }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(Envelope(version: 1, entries: Array(entries.prefix(100))))
            try data.write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { throw FlowError.storage }
    }
    public func clear() throws {
        if FileManager.default.fileExists(atPath: url.path) { do { try FileManager.default.removeItem(at: url) } catch { throw FlowError.storage } }
    }
}
