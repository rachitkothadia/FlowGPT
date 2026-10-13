import Foundation
import Testing
@testable import FlowCore

struct Flow2Tests {
    @Test func credentialPersistsAcrossStoreInstancesAndDeletes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("key.txt")
        let store = APIKeyStore(url: url)
        #expect(try store.load() == "")
        try store.save(" test-only ")
        #expect(try APIKeyStore(url: url).load() == "test-only")
        try store.save("replacement-only")
        #expect(try store.load() == "replacement-only")
        #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int == 0o600)
        try store.delete()
        #expect(try APIKeyStore(url: url).load() == "")
    }
    @Test func emptyAndInvalidCredentialsFailBeforeRequest() throws {
        for value in ["", "   ", "bad\nheader", "bad\0key"] {
            #expect(throws: (any Error).self) { try APIKeyStore.validated(value) }
            #expect(throws: (any Error).self) { try GroqRequest.completion(text: "Test", key: value, preferences: Preferences()) }
        }
    }
    @Test func marathiUsesFullWhisperWithLanguageHint() throws {
        var preferences = Preferences(); preferences.language = "mr"
        let request = try GroqRequest.transcription(audio: Data([1]), key: "test-only", preferences: preferences)
        let body = String(decoding: request.httpBody!, as: UTF8.self)
        #expect(body.contains("\r\n\r\nwhisper-large-v3\r\n"))
        #expect(body.contains("\r\n\r\nmr\r\n"))
        #expect(GroqRequest.speechModel(for: Preferences()) == "whisper-large-v3")
        var fast = Preferences(); fast.accuracy = "Fast"
        #expect(GroqRequest.speechModel(for: fast) == "whisper-large-v3-turbo")
    }
    @Test func rawTranscriptIsReturnedWithoutLocalRewriting() async throws {
        let transport = MockTransport(); let client = GroqClient(transport: transport)
        var preferences = Preferences(); preferences.cleanup = false
        let source = "Hello — world. नमस्ते। माझं नाव."
        #expect(try await client.clean(text: source, key: "", preferences: preferences) == source)
        #expect(await transport.count() == 0)
    }
    @Test @MainActor func ownAppTipDoesNotStartMicrophone() {
        let audio = MockAudio(); let session = SessionController(audio: audio, pipeline: MockPipeline(), insertion: MockInsertion())
        session.showTip()
        #expect(session.state == .tip)
        #expect(audio.starts == 0)
        session.dismiss(); #expect(session.state == .idle)
    }
}
