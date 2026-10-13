import Foundation

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}
public final class SessionTransport: NSObject, HTTPTransport, URLSessionTaskDelegate, @unchecked Sendable {
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 45; config.timeoutIntervalForResource = 90
        config.urlCache = nil; config.httpCookieStorage = nil
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    public override init() { super.init() }
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, data.count <= 2_000_000 else { throw FlowError.malformedResponse }
        return (data, http)
    }
    // Never follow redirects carrying the user's credential to another origin.
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
public protocol TextPipeline: Sendable {
    func transcribe(audio: URL, key: String, preferences: Preferences) async throws -> String
    func clean(text: String, key: String, preferences: Preferences) async throws -> String
}
public enum GroqRequest {
    public static let base = "https://api.groq.com/openai/v1"
    public static let speechModel = "whisper-large-v3-turbo"
    public static let textModel = "openai/gpt-oss-120b"
    public static func speechModel(for preferences: Preferences) -> String {
        preferences.accuracy != "Fast" || preferences.language == "mr" ? "whisper-large-v3" : speechModel
    }
    static func request(path: String, key: String) throws -> URLRequest {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !key.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw FlowError.missingKey }
        var request = URLRequest(url: URL(string: base + path)!)
        request.httpMethod = "POST"; request.timeoutInterval = 45
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        return request
    }
    public static func transcription(audio: Data, key: String, preferences: Preferences, boundary: String = "Flow-" + UUID().uuidString) throws -> URLRequest {
        guard !audio.isEmpty, audio.count <= 24_000_000 else { throw FlowError.audioTooLarge }
        var request = try request(path: "/audio/transcriptions", key: key)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        func append(_ value: String) { body.append(Data(value.utf8)) }
        var fields = [("model", speechModel(for: preferences)), ("response_format", "json"), ("temperature", "0")]
        if let hint = LanguageCatalog.requestHint(preferences.language) { fields.append(("language", hint)) }
        for (name, value) in fields { append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n") }
        let isWave = audio.count >= 12 && audio.prefix(4) == Data("RIFF".utf8) && audio[8..<12] == Data("WAVE".utf8)
        let filename = isWave ? "dictation.wav" : "dictation.m4a"
        let contentType = isWave ? "audio/wav" : "audio/mp4"
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: \(contentType)\r\n\r\n")
        body.append(audio); append("\r\n--\(boundary)--\r\n")
        request.httpBody = body
        return request
    }
    public static func completion(text: String, key: String, preferences: Preferences) throws -> URLRequest {
        var request = try request(path: "/chat/completions", key: key)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": textModel, "temperature": 0,
            "max_completion_tokens": min(8192, max(1536, text.utf8.count * 2 + 512)),
            "reasoning_effort": "low", "include_reasoning": false, "stream": false,
            "messages": [["role": "system", "content": preferences.mode.prompt(custom: preferences.customInstructions)],
                         ["role": "user", "content": try TextValidation.validate(text)]]
        ] as [String: Any])
        return request
    }
    public static func textProbe(key: String) throws -> URLRequest {
        var request = try request(path: "/chat/completions", key: key)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": textModel, "temperature": 0, "max_completion_tokens": 512,
            "reasoning_effort": "low", "include_reasoning": false, "stream": false,
            "response_format": ["type": "json_object"],
            "messages": [["role": "system", "content": "For this connection test, return exactly this JSON object: {\"text\":\"OK\"}"],
                         ["role": "user", "content": "Run the connection test."]]
        ] as [String: Any])
        return request
    }
    public static func parseTranscription(_ data: Data) throws -> String {
        struct Response: Decodable { let text: String }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { throw FlowError.malformedResponse }
        return try TextValidation.validate(response.text)
    }
    public static func parseCompletion(_ data: Data) throws -> String {
        struct Response: Decodable {
            struct Choice: Decodable { struct Message: Decodable { let content: String?; let role: String }; let message: Message; let finish_reason: String? }
            let choices: [Choice]
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data), response.choices.count == 1,
              let choice = response.choices.first, choice.message.role == "assistant", choice.finish_reason == "stop",
              let content = choice.message.content else { throw FlowError.malformedResponse }
        return try TextValidation.validate(content)
    }
}
public struct ModelProbeResult: Sendable, Equatable {
    public let statusCode: Int?
    public let message: String
    public var passed: Bool { statusCode == 200 }
    public init(statusCode: Int?, message: String) { self.statusCode = statusCode; self.message = message }
}
public actor GroqClient: TextPipeline {
    private let transport: any HTTPTransport
    public init(transport: any HTTPTransport = SessionTransport()) { self.transport = transport }
    private func perform(_ request: URLRequest) async throws -> Data {
        for attempt in 0...1 {
            try Task.checkCancellation()
            do {
                let (data, response) = try await transport.send(request)
                try Task.checkCancellation()
                if (200..<300).contains(response.statusCode) { return data }
                if response.statusCode == 401 || response.statusCode == 403 { throw FlowError.authentication }
                if response.statusCode == 429 {
                    if attempt == 0 {
                        let requested = Double(response.value(forHTTPHeaderField: "Retry-After") ?? "1") ?? 1
                        guard requested <= 3 else { throw FlowError.rateLimited }
                        let delay = max(0.1, requested)
                        try await Task.sleep(for: .seconds(delay)); continue
                    }
                    throw FlowError.rateLimited
                }
                // Do not retry uncertain POST/network failures: the server may already have billed the operation.
                throw FlowError.service(response.statusCode)
            } catch is CancellationError { throw CancellationError() }
            catch let error as FlowError { throw error }
            catch let error as URLError {
                if error.code == .cancelled { throw CancellationError() }
                throw error.code == .timedOut ? FlowError.timeout : FlowError.network
            } catch { throw FlowError.network }
        }
        throw FlowError.rateLimited
    }
    public func transcribe(audio: URL, key: String, preferences: Preferences) async throws -> String {
        try Task.checkCancellation()
        let data = try Data(contentsOf: audio, options: .mappedIfSafe)
        return try GroqRequest.parseTranscription(await perform(GroqRequest.transcription(audio: data, key: key, preferences: preferences)))
    }
    public func clean(text: String, key: String, preferences: Preferences) async throws -> String {
        let source = try TextValidation.validate(text)
        if !preferences.cleanup || preferences.mode == .verbatim { return source }
        let data = try await perform(GroqRequest.completion(text: source, key: key, preferences: preferences))
        return try GroqRequest.parseCompletion(data)
    }
    private func probe(_ request: URLRequest) async throws -> ModelProbeResult {
        try Task.checkCancellation()
        do {
            let (data, response) = try await transport.send(request)
            try Task.checkCancellation()
            let code = response.statusCode
            var message = code == 200 ? "HTTP 200 · Ready" : code == 401 || code == 403 ? "HTTP \(code) · Check your API key" : code == 429 ? "HTTP 429 · Rate limit reached" : "HTTP \(code) · Request failed"
            if code != 200,
               let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = body["error"] as? [String: Any], let detail = error["message"] as? String {
                // Never expose a echoed credential or failed_generation content.
                let credential = request.value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(of: "Bearer ", with: "") ?? ""
                let safe = credential.isEmpty ? detail : detail.replacingOccurrences(of: credential, with: "[redacted]")
                message += " · " + String(safe.filter { !$0.isNewline }.prefix(400))
            }
            return ModelProbeResult(statusCode: code, message: message)
        } catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch { return ModelProbeResult(statusCode: nil, message: "Network request failed. Check your connection.") }
    }
    public func testSpeech(key: String, sample: Data) async throws -> ModelProbeResult {
        try await probe(GroqRequest.transcription(audio: sample, key: key, preferences: Preferences()))
    }
    public func testText(key: String) async throws -> ModelProbeResult {
        try await probe(GroqRequest.textProbe(key: key))
    }
    public func testConnection(key: String) async throws {
        var request = try GroqRequest.request(path: "/models", key: key); request.httpMethod = "GET"
        let data = try await perform(request)
        struct Models: Decodable { struct Model: Decodable { let id: String }; let data: [Model] }
        guard let models = try? JSONDecoder().decode(Models.self, from: data), [GroqRequest.speechModel, GroqRequest.textModel].allSatisfy({ id in models.data.contains { $0.id == id } }) else { throw FlowError.malformedResponse }
    }
}
