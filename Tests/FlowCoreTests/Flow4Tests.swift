import Foundation
import Testing
@testable import FlowCore

struct Flow4Tests {
    @Test func formatterOutputIsDeliveredWithoutLocalCorrectionsOrRejection() async throws {
        let output = "मुझे समझ नहीं आ रहा कि what should I delete from my storage, क्योंकि मेरे पास storage ही नहीं है।"
        let envelope: [String: Any] = ["choices": [["message": ["role": "assistant", "content": output], "finish_reason": "stop"]]]
        let body = String(decoding: try JSONSerialization.data(withJSONObject: envelope), as: UTF8.self)
        let transport = MockTransport(body: body)
        let client = GroqClient(transport: transport)
        let source = "मुझे समझ नहीं हारा what should I delete from my storage ब्युक्ति मेरे पास स्टोरेज ही नहीं है"
        #expect(try await client.clean(text: source, key: "test-only", preferences: Preferences()) == output)
        let requests = await transport.requests
        #expect(requests.count == 1)
        let payload = try #require(JSONSerialization.jsonObject(with: requests[0].httpBody!) as? [String: Any])
        let messages = try #require(payload["messages"] as? [[String: String]])
        #expect(messages[1]["content"] == source)
        #expect(payload["response_format"] == nil)
    }
    @Test func legacyIntelligenceSettingsAreIgnoredWithoutLosingRecordingPreferences() throws {
        let json = """
        {"mode":"Clean Dictation","cleanup":true,"customInstructions":"","language":"","vocabulary":"wrong=override","domain":"Programming and technical","phraseCorrections":true,"shortcut":{"keyCode":49,"modifiers":8388608,"label":"Fn + Space"},"shortcutEnabled":true,"pushToTalk":false,"showPanel":true,"autoDismiss":true,"historyEnabled":true,"preserveClipboard":true,"backgroundLaunch":true,"appearance":"System","continuous":true,"accuracy":"Accurate","audioSource":"Microphone"}
        """
        let preferences = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
        #expect(preferences.isContinuous)
        #expect(preferences.historyEnabled)
        let saved = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences)) as? [String: Any])
        #expect(saved["vocabulary"] == nil && saved["domain"] == nil && saved["phraseCorrections"] == nil)
    }
    @Test func oneInputKeepsAllLanguagesAndHasNoForcedLanguageByDefault() throws {
        let source = "मुझे storage चाहिए. मला update करायचं आहे. Check the database. আমাকে পরে বলো।"
        let request = try GroqRequest.completion(text: source, key: "test-only", preferences: Preferences())
        let payload = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        let messages = try #require(payload["messages"] as? [[String: String]])
        #expect(messages[1]["content"] == source)
        let speech = try GroqRequest.transcription(audio: Data([1]), key: "test-only", preferences: Preferences())
        let multipart = String(decoding: speech.httpBody!, as: UTF8.self)
        #expect(!multipart.contains("name=\"language\""))
        #expect(!multipart.contains("name=\"prompt\""))
    }
}

struct Flow402LongListTests {
    @Test func twoHundredItemsReachFormatterAndInsertionTextWithoutClipping() async throws {
        let source = (1...200).map { "item \($0)" }.joined(separator: ", ")
        let output = (1...200).map { "\($0). item \($0)" }.joined(separator: "\n")
        let envelope: [String: Any] = ["choices": [["message": ["role": "assistant", "content": output], "finish_reason": "stop"]]]
        let body = String(decoding: try JSONSerialization.data(withJSONObject: envelope), as: UTF8.self)
        let transport = MockTransport(body: body)
        let result = try await GroqClient(transport: transport).clean(text: source, key: "test-only", preferences: Preferences())
        #expect(result == output)
        #expect(result.split(separator: "\n").count == 200)
        let requests = await transport.requests
        let payload = try #require(JSONSerialization.jsonObject(with: requests[0].httpBody!) as? [String: Any])
        let messages = try #require(payload["messages"] as? [[String: String]])
        #expect(messages[1]["content"] == source)
    }
    @Test func longBulletsArrowsAndMixedScriptsAreDeliveredExactly() async throws {
        let output = (1...40).map { "• काम \($0): request → response, मराठी शब्द आणि English words।" }.joined(separator: "\n")
        let envelope: [String: Any] = ["choices": [["message": ["role": "assistant", "content": output], "finish_reason": "stop"]]]
        let body = String(decoding: try JSONSerialization.data(withJSONObject: envelope), as: UTF8.self)
        let result = try await GroqClient(transport: MockTransport(body: body)).clean(text: "Forty mixed language points", key: "test-only", preferences: Preferences())
        #expect(result == output)
        #expect(result.split(separator: "\n").count == 40)
    }
}
