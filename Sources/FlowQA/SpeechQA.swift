import Foundation
import AVFoundation
import FlowCore

actor QAHTTPTransport: HTTPTransport {
    private let transport = SessionTransport()
    private var statuses: [Int] = []
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let result = try await transport.send(request)
        statuses.append(result.1.statusCode)
        return result
    }
    func drain() -> [Int] { let result = statuses; statuses = []; return result }
}
struct SpeechEvaluation: Codable {
    var id: String
    var reference: String
    var raw: String
    var output: String
    var statusCodes: [Int]
    var wordErrorRate: Double
    var retainedWords: Bool
    var latencySeconds: Double
    var error: String?
}
enum SpeechQA {
    static func smoke(directory: URL, key: String) async throws {
        let transport = QAHTTPTransport(), client = GroqClient(transport: transport)
        var results: [SpeechEvaluation] = []
        for (language, _, texts) in samples.prefix(2) {
            for sector in 0...1 {
                let id = "\(language)-\(sector)-normal"
                let audio = directory.appendingPathComponent(id + ".wav")
                let start = Date()
                var raw = "", output = "", failure: String?
                do {
                    raw = try await client.transcribe(audio: audio, key: key, preferences: Preferences())
                    do { output = try await client.clean(text: raw, key: key, preferences: Preferences()) }
                    catch { output = raw; failure = "Formatting unavailable: " + error.localizedDescription }
                } catch { failure = error.localizedDescription }
                let statuses = await transport.drain()
                results.append(SpeechEvaluation(id: id, reference: texts[sector], raw: raw, output: output,
                    statusCodes: statuses, wordErrorRate: wer(texts[sector], raw), retainedWords: words(raw) == words(output),
                    latencySeconds: Date().timeIntervalSince(start), error: failure))
                print("\(id): HTTP \(statuses) · \(failure ?? "completed")"); fflush(stdout)
            }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(results).write(to: URL(fileURLWithPath: "QA/flow40-speech-smoke-results.json"), options: .atomic)
    }
    static func compare(directory: URL, key: String, technical: Bool = false) async throws {
        let transport = QAHTTPTransport(), client = GroqClient(transport: transport)
        var results: [SpeechEvaluation] = []
        for (language, _, texts) in samples {
            let audio = directory.appendingPathComponent(language + "-1-normal.wav")
            guard FileManager.default.fileExists(atPath: audio.path) else { continue }
            var prefs = Preferences(); prefs.language = language; prefs.accuracy = technical ? "Fast" : "Accurate"
            let label = technical ? "turbo" : "full-v3"
            let start = Date(); var raw = "", failure: String?
            do { raw = try await client.transcribe(audio: audio, key: key, preferences: prefs) }
            catch { failure = error.localizedDescription }
            results.append(SpeechEvaluation(id: language + "-1-" + label, reference: texts[1], raw: raw, output: raw, statusCodes: await transport.drain(), wordErrorRate: wer(texts[1], raw), retainedWords: true, latencySeconds: Date().timeIntervalSince(start), error: failure))
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(results).write(to: directory.appendingPathComponent(label + "-comparison.json"), options: .atomic)
            print("\(language) \(label): WER \(results.last!.wordErrorRate) · HTTP \(results.last!.statusCodes)"); fflush(stdout)
            try await Task.sleep(for: .seconds(8))
        }
    }
    static let samples: [(String, String, [String])] = [
        ("en", "Rishi", ["Buy cumin, coriander, oat milk and two packets of rice. Do not buy hot sauce.", "Today we discuss Rust, Kotlin, Swift and SQL. The frontend needs a database.", "The meeting starts at ten. Record the budget and do not change the deadline."]),
        ("hi", "Lekha", ["मुझे जीरा, धनिया और दो किलो चावल चाहिए। गरम मसाला लेना, सॉस मत लेना।", "आज हम inheritance और constructor सीखेंगे। frontend के साथ backend और database चाहिए।", "बैठक कल सुबह होगी। समय मत बदलना। मुझे तेरे से एक काम है।"]),
        ("bn", "Piya", ["আমার চাল, ডাল এবং দুধ দরকার। দুই কিলো চাল কিনুন।", "আজ আমরা frontend এবং backend শিখব। database পরে তৈরি হবে।", "সভা আগামীকাল সকালে হবে। সময় পরিবর্তন করবেন না।"]),
        ("ta", "Vani", ["எனக்கு அரிசி, பருப்பு மற்றும் பால் வேண்டும். இரண்டு கிலோ அரிசி வாங்குங்கள்.", "இன்று frontend மற்றும் backend பற்றி பேசுவோம். database பின்னர் உருவாக்கலாம்.", "கூட்டம் நாளை காலை நடைபெறும். நேரத்தை மாற்ற வேண்டாம்."]),
        ("te", "Geeta", ["నాకు బియ్యం, పప్పు మరియు పాలు కావాలి. రెండు కిలోల బియ్యం కొనండి.", "ఈ రోజు frontend మరియు backend నేర్చుకుందాం. database తర్వాత తయారు చేద్దాం.", "సమావేశం రేపు ఉదయం జరుగుతుంది. సమయాన్ని మార్చవద్దు."]),
        ("kn", "Soumya", ["ನನಗೆ ಅಕ್ಕಿ, ಬೇಳೆ ಮತ್ತು ಹಾಲು ಬೇಕು. ಎರಡು ಕಿಲೋ ಅಕ್ಕಿ ಖರೀದಿಸಿ.", "ಇಂದು frontend ಮತ್ತು backend ಬಗ್ಗೆ ಮಾತನಾಡೋಣ. database ನಂತರ ಮಾಡೋಣ.", "ಸಭೆ ನಾಳೆ ಬೆಳಿಗ್ಗೆ ನಡೆಯುತ್ತದೆ. ಸಮಯವನ್ನು ಬದಲಾಯಿಸಬೇಡಿ."])
    ]
    static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
    static func wer(_ reference: String, _ hypothesis: String) -> Double {
        let a = words(reference), b = words(hypothesis)
        var row = Array(0...b.count)
        for (i, x) in a.enumerated() {
            var next = [i + 1]
            for (j, y) in b.enumerated() { next.append(min(row[j + 1] + 1, next[j] + 1, row[j] + (x == y ? 0 : 1))) }
            row = next
        }
        return Double(row.last ?? 0) / Double(max(1, a.count))
    }
    static func run(directory: URL, key: String, languages: Set<String>? = nil, reuseAudio: Bool = false) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let transport = QAHTTPTransport(), client = GroqClient(transport: transport)
        var results: [SpeechEvaluation] = []
        for (language, voice, texts) in samples where languages == nil || languages!.contains(language) {
            for (sector, reference) in texts.enumerated() {
                for (condition, rate) in [("normal", 175), ("fast", 240), ("quiet", 175)] {
                    let id = "\(language)-\(sector)-\(condition)", audio = directory.appendingPathComponent(id + ".wav")
                    if !reuseAudio {
                    let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
                    process.arguments = ["-v", voice, "-r", String(rate), "--file-format=WAVE", "--data-format=LEI16@16000", "-o", audio.path, reference]
                    try process.run(); process.waitUntilExit()
                    guard process.terminationStatus == 0 else { throw FlowError.recording }
                    if condition == "quiet" { try attenuate(audio) }
                    }
                    guard FileManager.default.fileExists(atPath: audio.path) else { throw FlowError.recording }
                    var prefs = Preferences(); prefs.language = ""
                    let start = Date(); var raw = "", output = "", failure: String?
                    do {
                        raw = try await client.transcribe(audio: audio, key: key, preferences: prefs)
                        output = try await client.clean(text: raw, key: key, preferences: prefs)
                    } catch { failure = error.localizedDescription }
                    let retained = !raw.isEmpty && words(raw) == words(output)
                    results.append(SpeechEvaluation(id: id, reference: reference, raw: raw, output: output, statusCodes: await transport.drain(), wordErrorRate: wer(reference, raw), retainedWords: retained, latencySeconds: Date().timeIntervalSince(start), error: failure))
                    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    try encoder.encode(results).write(to: directory.appendingPathComponent(reuseAudio ? "recheck-results.json" : "results.json"), options: .atomic)
                    print("\(id): WER \(String(format: "%.3f", results.last!.wordErrorRate)) · HTTP \(results.last!.statusCodes) · \(failure ?? "completed")"); fflush(stdout)
                    try await Task.sleep(for: .seconds(8))
                }
            }
        }
    }
    static func attenuate(_ url: URL) throws {
        let input = try AVAudioFile(forReading: url)
        guard input.length < 1_000_000, let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: AVAudioFrameCount(input.length)) else { throw FlowError.recording }
        try input.read(into: buffer)
        guard let channels = buffer.floatChannelData else { throw FlowError.recording }
        for channel in 0..<Int(buffer.format.channelCount) { for index in 0..<Int(buffer.frameLength) { channels[channel][index] *= 0.15 } }
        let temporary = url.deletingPathExtension().appendingPathExtension("quiet.wav")
        do { let writer = try AVAudioFile(forWriting: temporary, settings: input.fileFormat.settings); try writer.write(from: buffer) }
        try FileManager.default.removeItem(at: url); try FileManager.default.moveItem(at: temporary, to: url)
    }
}
