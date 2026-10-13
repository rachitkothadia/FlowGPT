import Testing
import Foundation
@testable import FlowCore

actor MockTransport: HTTPTransport {
    var status: Int
    var body: Data
    var error: URLError?
    var delay: Duration
    var requests: [URLRequest] = []
    var headers: [String: String]
    init(status: Int = 200, body: String = "{\"text\":\"Hello.\"}", error: URLError? = nil, delay: Duration = .zero, headers: [String: String] = [:]) {
        self.status = status; self.body = Data(body.utf8); self.error = error; self.delay = delay; self.headers = headers
    }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if delay != .zero { try await Task.sleep(for: delay) }
        if let error { throw error }
        return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!)
    }
    func count() -> Int { requests.count }
}
struct GroqTests {
    @Test func testMultipartEndpointModelAndAuthentication() throws {
        var prefs = Preferences(); prefs.language = "hi"; prefs.accuracy = "Fast"
        let request = try GroqRequest.transcription(audio: Data([1, 2, 3]), key: "test-only", preferences: prefs, boundary: "TEST")
        #expect(request.url?.absoluteString ==  "https://api.groq.com/openai/v1/audio/transcriptions")
        #expect(request.value(forHTTPHeaderField: "Authorization") ==  "Bearer test-only")
        #expect(request.value(forHTTPHeaderField: "Content-Type") ==  "multipart/form-data; boundary=TEST")
        let body = String(decoding: request.httpBody!, as: UTF8.self)
        #expect(body.contains("whisper-large-v3-turbo")); #expect(body.contains("name=\"language\"\r\n\r\nhi"))
        #expect(!body.contains("name=\"prompt\"")); #expect(body.hasSuffix("\r\n--TEST--\r\n"))
        #expect(body.contains("filename=\"dictation.m4a\"")); #expect(body.contains("audio/mp4"))
    }
    @Test func testCompletionRequestModelReasoningAndContent() throws {
        var prefs = Preferences(); prefs.mode = .developer
        let request = try GroqRequest.completion(text: "hello file.swift", key: "test-only", preferences: prefs)
        #expect(request.url?.absoluteString ==  "https://api.groq.com/openai/v1/chat/completions")
        let json = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        #expect(json["model"] as? String ==  "openai/gpt-oss-120b")
        #expect(json["include_reasoning"] as? Bool ==  false)
        #expect(json["reasoning_format"] == nil)
        let messages = try #require(json["messages"] as? [[String: String]])
        #expect(messages[1]["content"] ==  "hello file.swift"); #expect(messages[0]["content"]!.contains("identifiers"))
    }
    @Test func testMissingKeyRejected() { #expect(throws: (any Error).self) { try GroqRequest.completion(text: "hi", key: "", preferences: Preferences()) } }
    @Test func testHeaderInjectionRejected() { #expect(throws: (any Error).self) { try GroqRequest.completion(text: "hi", key: "test\r\nHeader", preferences: Preferences()) } }
    @Test func testEmptyAudioRejected() { #expect(throws: (any Error).self) { try GroqRequest.transcription(audio: Data(), key: "test", preferences: Preferences()) } }
    @Test func testOversizedAudioRejected() { #expect(throws: (any Error).self) { try GroqRequest.transcription(audio: Data(repeating: 0, count: 24_000_001), key: "test", preferences: Preferences()) } }
    @Test func testWaveUploadPreservesAudioAndUsesWaveMetadata() throws {
        let audio = Data("RIFF0000WAVEtest-audio".utf8)
        let request = try GroqRequest.transcription(audio: audio, key: "test-only", preferences: Preferences(), boundary: "WAVE-TEST")
        let body = String(decoding: request.httpBody!, as: UTF8.self)
        #expect(body.contains("filename=\"dictation.wav\""))
        #expect(body.contains("Content-Type: audio/wav"))
        #expect(body.contains("RIFF0000WAVEtest-audio"))
    }
    @Test func testValidTranscription() throws { #expect(try GroqRequest.parseTranscription(Data("{\"text\":\" नमस्ते \"}".utf8)) ==  "नमस्ते") }
    @Test func testEmptyTranscript() { #expect(throws: (any Error).self) { try GroqRequest.parseTranscription(Data("{\"text\":\" \"}".utf8)) } }
    @Test func testMalformedTranscript() { #expect(throws: (any Error).self) { try GroqRequest.parseTranscription(Data("{\"text\":42}".utf8)) } }
    @Test func testValidCompletionIgnoresReasoningField() throws {
        let data = Data("{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"Hello.\",\"reasoning\":\"private\"},\"finish_reason\":\"stop\"}]}".utf8)
        #expect(try GroqRequest.parseCompletion(data) ==  "Hello.")
    }
    @Test func testRejectTruncatedCompletion() { #expect(throws: (any Error).self) { try GroqRequest.parseCompletion(Data("{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"hi\"},\"finish_reason\":\"length\"}]}".utf8)) } }
    @Test func testMalformedCompletion() { #expect(throws: (any Error).self) { try GroqRequest.parseCompletion(Data("{\"choices\":[]}".utf8)) } }
    @Test func testRejectReasoningAndNullOutput() { for text in ["<think>private</think>hello", "hi\0there"] { #expect(throws: (any Error).self) { try TextValidation.validate(text) } } }
    @Test func testModePromptsDifferAndEnforceMeaning() {
        let prompts = DictationMode.allCases.map { $0.prompt(custom: "Use short paragraphs") }
        #expect(Set(prompts).count ==  5)
        for prompt in prompts { #expect(prompt.contains("Never add facts")); #expect(prompt.contains("untrusted")) }
    }
    @Test func testCustomInstructionsBounded() { #expect(DictationMode.custom.prompt(custom: String(repeating: "a", count: 10_000)).count - DictationMode.custom.prompt(custom: "").count == 2000) }
    @Test func testRawModeDoesNotCallAPI() async throws {
        let mock = MockTransport(); let client = GroqClient(transport: mock); var prefs = Preferences(); prefs.cleanup = false
        let result = try await client.clean(text: "raw wording", key: "", preferences: prefs)
        #expect(result ==  "raw wording"); let count = await mock.count(); #expect(count ==  0)
    }
    private func expect(_ status: Int, _ expected: FlowError) async {
        let client = GroqClient(transport: MockTransport(status: status, headers: ["Retry-After": "0.1"]))
        do { _ = try await client.clean(text: "hi", key: "test", preferences: Preferences()); Issue.record("Expected API failure") }
        catch { #expect(error as? FlowError ==  expected) }
    }
    @Test func testInvalidCredential() async { await expect(401, .authentication) }
    @Test func testForbiddenCredential() async { await expect(403, .authentication) }
    @Test func testRateLimitBounded() async {
        let mock = MockTransport(status: 429, headers: ["Retry-After": "0.1"]); let client = GroqClient(transport: mock)
        do { _ = try await client.clean(text: "hi", key: "test", preferences: Preferences()); Issue.record("Unexpected success") } catch { #expect(error as? FlowError ==  .rateLimited) }
        let count = await mock.count(); #expect(count ==  2)
    }
    @Test func testLongRetryAfterDoesNotRetryTooSoon() async {
        let mock = MockTransport(status: 429, headers: ["Retry-After": "120"]); let client = GroqClient(transport: mock)
        do { _ = try await client.clean(text: "hi", key: "test", preferences: Preferences()); Issue.record("Unexpected success") } catch { #expect(error as? FlowError ==  .rateLimited) }
        let requests = await mock.requests; #expect(requests.count == 1)
        let models = try? requests.map { request in (try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any])["model"] as! String }
        #expect(models == [GroqRequest.textModel])
    }
    @Test func testServerError() async { await expect(503, .service(503)) }
    @Test func testUnsupportedAudioStatus() async { await expect(400, .service(400)) }
    @Test func testRedirectIsNotSuccess() async { await expect(302, .service(302)) }
    @Test func testTimeout() async { await networkError(.timedOut, expected: .timeout) }
    @Test func testNetworkFailure() async { await networkError(.notConnectedToInternet, expected: .network) }
    @Test func testDNSFailure() async { await networkError(.cannotFindHost, expected: .network) }
    private func networkError(_ code: URLError.Code, expected: FlowError) async {
        let mock = MockTransport(error: URLError(code)); let client = GroqClient(transport: mock)
        do { _ = try await client.clean(text: "hi", key: "test", preferences: Preferences()); Issue.record("Unexpected success") } catch { #expect(error as? FlowError ==  expected) }
        let count = await mock.count(); #expect(count ==  1)
    }
    @Test func testRequestCancellation() async {
        let client = GroqClient(transport: MockTransport(delay: .seconds(5)))
        let task = Task { try await client.clean(text: "hi", key: "test", preferences: Preferences()) }
        task.cancel()
        do { _ = try await task.value; Issue.record("Unexpected success") } catch { #expect(error is CancellationError) }
    }
    @Test func testConnectionChecksBothModels() async throws {
        let mock = MockTransport(body: "{\"data\":[{\"id\":\"whisper-large-v3-turbo\"},{\"id\":\"openai/gpt-oss-120b\"}]}")
        try await GroqClient(transport: mock).testConnection(key: "test")
        let requests = await mock.requests; #expect(requests.first?.httpMethod ==  "GET"); #expect(requests.first!.url!.path.hasSuffix("/models"))
    }
    @Test func testConnectionMissingModelFails() async {
        do { try await GroqClient(transport: MockTransport(body: "{\"data\":[]}")).testConnection(key: "test"); Issue.record("Unexpected success") } catch { #expect(error as? FlowError ==  .malformedResponse) }
    }
    @Test func testSpeechProbePostsActualAudioAndReports200() async throws {
        let mock = MockTransport(); let client = GroqClient(transport: mock)
        let result = try await client.testSpeech(key: "test-only", sample: Data([1, 2, 3]))
        #expect(result.passed); #expect(result.statusCode == 200)
        let requests = await mock.requests
        #expect(requests.count == 1); #expect(requests[0].httpMethod == "POST")
        #expect(requests[0].url?.path == "/openai/v1/audio/transcriptions")
        #expect(requests[0].httpBody?.contains(Data([1, 2, 3])) == true)
    }
    @Test func testTextProbePostsActualCompletion() async throws {
        let mock = MockTransport(); let result = try await GroqClient(transport: mock).testText(key: "test-only")
        #expect(result.passed)
        let requests = await mock.requests
        #expect(requests[0].url?.path == "/openai/v1/chat/completions")
        let body = try #require(JSONSerialization.jsonObject(with: requests[0].httpBody!) as? [String: Any])
        #expect(body["model"] as? String == "openai/gpt-oss-120b")
        #expect(body["max_completion_tokens"] as? Int == 512)
    }
    @Test func testProbeRequiresExactly200AndDoesNotRetry() async throws {
        for code in [201, 204, 302, 400, 401, 403, 429, 503] {
            let mock = MockTransport(status: code)
            let result = try await GroqClient(transport: mock).testText(key: "test-only")
            #expect(!result.passed); #expect(result.statusCode == code)
            #expect(await mock.count() == 1)
        }
    }
    @Test func connectionProbeUsesSmallConsistentJSONPrompt() throws {
        let request = try GroqRequest.textProbe(key: "test-only")
        let body = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages.count == 2)
        #expect(messages[0]["content"]?.contains("JSON") == true)
        #expect(messages[1]["content"] == "Run the connection test.")
        #expect(body["reasoning_effort"] as? String == "low")
        #expect(request.httpBody!.count < 700)
    }
    @Test func providerErrorDetailRedactsKeyAndOmitsGeneration() async throws {
        let mock = MockTransport(status: 400, body: "{\"error\":{\"message\":\"Invalid request for test-only\",\"failed_generation\":\"private generated content\"}}")
        let result = try await GroqClient(transport: mock).testText(key: "test-only")
        #expect(result.message.contains("Invalid request"))
        #expect(result.message.contains("[redacted]"))
        #expect(!result.message.contains("test-only"))
        #expect(!result.message.contains("private generated content"))
    }
    @Test func testProbeNetworkFailureDoesNotClaimHTTPStatus() async throws {
        let result = try await GroqClient(transport: MockTransport(error: URLError(.notConnectedToInternet))).testText(key: "test-only")
        #expect(!result.passed); #expect(result.statusCode == nil)
    }
    @Test func testProbeCancellationDoesNotReturnFailureResult() async {
        let client = GroqClient(transport: MockTransport(delay: .seconds(5)))
        let task = Task { try await client.testText(key: "test-only") }; task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") } catch { #expect(error is CancellationError) }
    }

}
