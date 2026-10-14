import Foundation
import Testing
@testable import FlowCore
struct Flow12Tests {
    struct Fixture: Decodable { let name: String; let input: String; let expected: String }
    @Test func sharedFormattingCases() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: root.appendingPathComponent("Shared/Tests/formatting.json")))
        for fixture in fixtures {
            let output = ConservativeFormatting.format(fixture.input)
            #expect(output == fixture.expected, Comment(rawValue: fixture.name))
            #expect(ConservativeFormatting.format(output) == output, Comment(rawValue: "Idempotent: " + fixture.name))
        }
    }
}
extension Flow12Tests {
    @Test func livePermissionContextWinsAndNoGrantIsInvented() {
        #expect(PermissionReading(microphone: true, accessibility: true, inputMonitoring: true).needsRestart == false)
        let deniedHelper = PermissionReading(microphone: true, accessibility: true, inputMonitoring: true, helperAccessibility: false, helperInput: false)
        #expect(deniedHelper.microphone && deniedHelper.accessibility && deniedHelper.inputMonitoring && !deniedHelper.needsRestart)
        let stale = PermissionReading(microphone: false, accessibility: false, inputMonitoring: false, helperAccessibility: true, helperInput: true)
        #expect(!stale.microphone && !stale.accessibility && !stale.inputMonitoring && stale.needsRestart)
        #expect(!PermissionReading(microphone: false, accessibility: false, inputMonitoring: false).needsRestart)
    }
}
