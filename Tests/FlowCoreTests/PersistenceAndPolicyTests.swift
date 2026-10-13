import Foundation
import Testing
@testable import FlowCore

struct PersistenceAndPolicyTests {
    @Test func testShortcutFnAndFallback() {
        #expect(Shortcut.fnSpace.matches(code: 49, flags: 1 << 23)); #expect(!(Shortcut.fnSpace.matches(code: 49, flags: 0)))
        #expect(!(Shortcut.fnSpace.matches(code: 49, flags: (1 << 23) | (1 << 20))))
        #expect(Shortcut.fallback.matches(code: 49, flags: (1 << 18) | (1 << 19)))
    }
    @Test func testShortcutRejectsNoModifierAndModifierKeys() {
        #expect(!(Shortcut(keyCode: 49, modifiers: 0, label: "Space").isValid))
        #expect(!(Shortcut(keyCode: 63, modifiers: 1 << 23, label: "Fn").isValid))
    }
    @Test func testShortcutRepeatAndReleaseDeduplication() {
        var interpreter = ShortcutInterpreter()
        #expect(interpreter.keyDown(matches: false, isRepeat: false) ==  .none)
        #expect(interpreter.keyDown(matches: true, isRepeat: true) ==  .none)
        #expect(interpreter.keyDown(matches: true, isRepeat: false) ==  .press)
        #expect(interpreter.keyDown(matches: true, isRepeat: false) ==  .none)
        #expect(interpreter.release() ==  .release); #expect(interpreter.release() ==  .none)
        #expect(interpreter.keyDown(matches: true, isRepeat: false) ==  .press); interpreter.reset(); #expect(!(interpreter.held))
    }
    @Test func testClipboardRestorationSafeguard() {
        #expect(ClipboardGuard.mayRestore(writtenCount: 10, currentCount: 10))
        #expect(!(ClipboardGuard.mayRestore(writtenCount: 10, currentCount: 11)))
    }
    @Test func testLoginConfigurationIdempotent() {
        #expect(!(LoginPolicy.needsChange(enabled: true, currentlyEnabled: true)))
        #expect(!(LoginPolicy.needsChange(enabled: false, currentlyEnabled: false)))
        #expect(LoginPolicy.needsChange(enabled: true, currentlyEnabled: false))
        #expect(LoginPolicy.needsChange(enabled: false, currentlyEnabled: true))
    }
    @Test func testConservativeDefaults() {
        let prefs = Preferences(); #expect(!(prefs.historyEnabled)); #expect(prefs.preserveClipboard); #expect(prefs.shortcut ==  .fnSpace); #expect(prefs.mode ==  .clean)
    }
    @Test func testPreferenceSanitization() {
        var prefs = Preferences(); prefs.language = "EN"; prefs.appearance = "garbage"
        prefs.shortcut = Shortcut(keyCode: 49, modifiers: 0, label: "Bad"); prefs.sanitize()
        #expect(prefs.language ==  "en"); #expect(prefs.appearance ==  "System"); #expect(prefs.shortcut ==  .fnSpace)
        prefs.language = "english"; prefs.sanitize(); #expect(prefs.language ==  "")
    }
    @Test func testSettingsPersistence() throws {
        let suite = "Flow-tests-" + UUID().uuidString; let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var prefs = Preferences(); prefs.mode = .developer; prefs.pushToTalk = true; prefs.shortcut = .fallback
        try PreferenceStore.save(prefs, to: defaults); #expect(try PreferenceStore.load(from: defaults) ==  prefs)
        #expect(!(String(decoding: defaults.data(forKey: "preferences.v1")!, as: UTF8.self).contains("apiKey")))
    }
    @Test func testCorruptedSettingsReported() {
        let suite = "Flow-tests-" + UUID().uuidString; let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("invalid".utf8), forKey: "preferences.v1"); #expect(throws: (any Error).self) { try PreferenceStore.load(from: defaults) }
    }
    @Test func testHistorySaveLoadDeleteAndPrivatePermissions() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Flow-history-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.json"); let store = HistoryStore(url: url)
        let entry = DictationResult(raw: "raw", final: "Final.", mode: .clean)
        try await store.save([entry]); let saved = try await store.load(); #expect(saved ==  [entry])
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int; #expect(permissions ==  0o600)
        try await store.clear(); let cleared = try await store.load(); #expect(cleared ==  [])
    }
    @Test func testHistoryBoundedTo100() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Flow-history-test-" + UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HistoryStore(url: url); try await store.save((0..<120).map { DictationResult(raw: "\($0)", final: "\($0)", mode: .clean) })
        let entries = try await store.load(); #expect(entries.count ==  100)
    }
    @Test func testCorruptHistoryIsReported() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Flow-history-test-" + UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }; try Data("bad".utf8).write(to: url)
        do { _ = try await HistoryStore(url: url).load(); Issue.record("Unexpected success") } catch { #expect(error as? FlowError ==  .storage) }
    }
}
