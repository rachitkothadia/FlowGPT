import Foundation
import FlowCore

struct Case: Codable {
    var id: String
    var input: String
    var required: [String]
    var numbered: Int?
    var bullets: Int?
    var forbidden: [String]?
    var noList: Bool?
    var requiredAny: [[String]]?
    var ignoreCase: Bool?
}
struct Evaluation: Codable {
    var id: String
    var passed: Bool
    var output: String
    var latencySeconds: Double
    var failures: [String]
    var modelCandidate: String?
    var statusCode: Int?
    var rateLimit: [String: String]?
    var statusCodes: [Int]?
    var models: [String]?
    var finishReasons: [String]?
}
actor QATransport: HTTPTransport {
    private let transport = SessionTransport()
    var candidate: String?
    var status: Int?
    var rateLimit: [String: String] = [:]
    var statuses: [Int] = []
    var models: [String] = []
    var finishReasons: [String] = []
    func reset() { statuses = []; models = []; finishReasons = []; candidate = nil; status = nil; rateLimit = [:] }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let result = try await transport.send(request)
        statuses.append(result.1.statusCode)
        if let data = request.httpBody, let body = try JSONSerialization.jsonObject(with: data) as? [String: Any], let name = body["model"] as? String { models.append(name) }
        status = result.1.statusCode
        rateLimit = [:]
        for name in ["retry-after", "x-ratelimit-remaining-tokens", "x-ratelimit-reset-tokens", "x-ratelimit-remaining-requests", "x-ratelimit-reset-requests"] {
            if let value = result.1.value(forHTTPHeaderField: name) { rateLimit[name] = value }
        }
        let responseBody = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any]
        if let choice = (responseBody?["choices"] as? [[String: Any]])?.first {
            candidate = (choice["message"] as? [String: Any])?["content"] as? String
            finishReasons.append(choice["finish_reason"] as? String ?? "missing")
        }
        if result.1.statusCode == 429 {
            if let message = (responseBody?["error"] as? [String: Any])?["message"] as? String {
                let regex = try NSRegularExpression(pattern: "TPD|TPM|RPD|RPM|(?:Limit|Used|Requested) [0-9]+")
                let native = message as NSString
                let summary = regex.matches(in: message, range: NSRange(location: 0, length: native.length)).map { native.substring(with: $0.range) }.joined(separator: ", ")
                print("Quota summary: \(summary)")
            }
            print("Rate limit metadata: \(rateLimit)"); fflush(stdout)
        }
        return result
    }
}
@main struct FlowQA {
    static func main() async {
        let args = CommandLine.arguments
        guard (3...4).contains(args.count) else { print("Usage: FlowQA cases.json results.json [comparison-model]"); exit(2) }
        do {
            let keyURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Flow/api-key.txt")
            let key = try APIKeyStore(url: keyURL).load()
            guard !key.isEmpty else { throw FlowError.missingKey }
            if args[1] == "--probe" {
                let request = try GroqRequest.textProbe(key: key)
                let (data, response) = try await SessionTransport().send(request)
                print("GPT-OSS probe HTTP \(response.statusCode)")
                if response.statusCode != 200 {
                    print(String(data: data, encoding: .utf8)?.replacingOccurrences(of: key, with: "[redacted]") ?? "Unreadable error")
                }
                let sample = try Data(contentsOf: URL(fileURLWithPath: "Resources/ConnectionSample.m4a"))
                let speech = try await GroqClient().testSpeech(key: key, sample: sample)
                print("Whisper probe HTTP \(speech.statusCode.map(String.init) ?? "unavailable")")
                return
            }
            if args[1] == "--models" {
                var request = URLRequest(url: URL(string: GroqRequest.base + "/models")!)
                request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
                let (data, response) = try await SessionTransport().send(request)
                guard response.statusCode == 200 else { throw FlowError.service(response.statusCode) }
                let body = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let names = (body?["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }.sorted()
                try JSONEncoder().encode(names).write(to: URL(fileURLWithPath: args[2]), options: .atomic)
                print("Model catalogue HTTP 200; \(names.count) model IDs saved without credentials")
                return
            }
            if args[1] == "--speech4-smoke" {
                try await SpeechQA.smoke(directory: URL(fileURLWithPath: args[2]), key: key)
                return
            }
            if args[1] == "--compare" || args[1] == "--technical" {
                try await SpeechQA.compare(directory: URL(fileURLWithPath: args[2]), key: key, technical: args[1] == "--technical")
                return
            }
            if args[1] == "--speech" || args[1] == "--speech30" || args[1] == "--speech30-recheck" {
                try await SpeechQA.run(directory: URL(fileURLWithPath: args[2]), key: key, languages: args[1] == "--speech" ? nil : ["en", "hi"], reuseAudio: args[1] == "--speech30-recheck")
                return
            }
            let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
            let transport = QATransport()
            let client = GroqClient(transport: transport)
            var results: [Evaluation] = []
            for item in cases {
                await transport.reset()
                let preferences = Preferences()
                let start = Date()
                var output = "", failures: [String] = []
                do { output = try await client.clean(text: item.input, key: key, preferences: preferences) }
                catch { failures.append(error.localizedDescription) }
                let spacedOutput = output.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                let matchingOutput = item.ignoreCase == true ? spacedOutput.lowercased() : spacedOutput
                func containsRequired(_ token: String) -> Bool { matchingOutput.contains(item.ignoreCase == true ? token.lowercased() : token) }
                for token in item.required where !containsRequired(token) { failures.append("Missing: " + token) }
                for group in item.requiredAny ?? [] where !group.contains(where: containsRequired) { failures.append("Missing any of: " + group.joined(separator: ", ")) }
                if let count = item.numbered {
                    for number in 1...count where !spacedOutput.contains("\(number). ") { failures.append("Missing list item \(number)") }
                }
                let bulletCount = output.split(separator: "\n").filter { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).hasPrefix("• ") }.count
                if let count = item.bullets, bulletCount != count { failures.append("Expected \(count) bullets, got \(bulletCount)") }
                for token in item.forbidden ?? [] where containsRequired(token) { failures.append("Forbidden: " + token) }
                if item.noList == true, bulletCount > 0 || output.range(of: "(?m)^\\s*[0-9]+[.)]\\s+", options: .regularExpression) != nil { failures.append("Unexpected list") }
                if output.contains("—") { failures.append("Em dash") }
                results.append(Evaluation(id: item.id, passed: failures.isEmpty, output: output, latencySeconds: Date().timeIntervalSince(start), failures: failures, modelCandidate: await transport.candidate, statusCode: await transport.status, rateLimit: await transport.rateLimit, statusCodes: await transport.statuses, models: await transport.models, finishReasons: await transport.finishReasons))
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(results).write(to: URL(fileURLWithPath: args[2]), options: .atomic)
                print(item.id + ": " + (failures.isEmpty ? "PASS" : "FAIL")); fflush(stdout)
                try await Task.sleep(for: .seconds(2))
            }
            print("\(results.filter(\.passed).count)/\(results.count) live cases passed")
            exit(results.allSatisfy(\.passed) ? 0 : 1)
        } catch { print("Evaluation failed: \(error.localizedDescription)"); exit(1) }
    }
}
