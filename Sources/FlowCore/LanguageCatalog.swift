import Foundation

public struct SpokenLanguage: Sendable, Identifiable {
    public let name: String
    public let code: String
    public let dedicatedRecognition: Bool
    public var id: String { code }
}
public enum LanguageCatalog {
    // Provider language tokens, not a claim of native-speaker accuracy.
    public static let indian: [SpokenLanguage] = [
        .init(name: "Assamese · অসমীয়া", code: "as", dedicatedRecognition: true),
        .init(name: "Bengali · বাংলা", code: "bn", dedicatedRecognition: true),
        .init(name: "Bodo", code: "brx", dedicatedRecognition: false),
        .init(name: "Dogri", code: "doi", dedicatedRecognition: false),
        .init(name: "Gujarati · ગુજરાતી", code: "gu", dedicatedRecognition: true),
        .init(name: "Hindi · हिन्दी", code: "hi", dedicatedRecognition: true),
        .init(name: "Kannada · ಕನ್ನಡ", code: "kn", dedicatedRecognition: true),
        .init(name: "Kashmiri", code: "ks", dedicatedRecognition: false),
        .init(name: "Konkani", code: "kok", dedicatedRecognition: false),
        .init(name: "Maithili", code: "mai", dedicatedRecognition: false),
        .init(name: "Malayalam · മലയാളം", code: "ml", dedicatedRecognition: true),
        .init(name: "Manipuri / Meitei", code: "mni", dedicatedRecognition: false),
        .init(name: "Marathi · मराठी", code: "mr", dedicatedRecognition: true),
        .init(name: "Nepali · नेपाली", code: "ne", dedicatedRecognition: true),
        .init(name: "Odia · ଓଡ଼ିଆ", code: "or", dedicatedRecognition: false),
        .init(name: "Punjabi · ਪੰਜਾਬੀ", code: "pa", dedicatedRecognition: true),
        .init(name: "Sanskrit · संस्कृतम्", code: "sa", dedicatedRecognition: true),
        .init(name: "Santali", code: "sat", dedicatedRecognition: false),
        .init(name: "Sindhi · سنڌي", code: "sd", dedicatedRecognition: true),
        .init(name: "Tamil · தமிழ்", code: "ta", dedicatedRecognition: true),
        .init(name: "Telugu · తెలుగు", code: "te", dedicatedRecognition: true),
        .init(name: "Urdu · اردو", code: "ur", dedicatedRecognition: true)
    ]
    public static let supportedCodes: Set<String> = Set("en zh de es ru ko fr ja pt tr pl ca nl ar sv it id hi fi vi he uk el ms cs ro da hu ta no th ur hr bg lt la mi ml cy sk te fa lv bn sr az sl kn mk br eu is hy ne mn bs kk sq sw gl mr pa si km sn yo so af oc ka be tg sd gu am yi lo uz fo ht ps tk nn mt sa lb my bo tl mg as tt haw ln ha ba jw su yue".split(separator: " ").map(String.init))
    public static func requestHint(_ code: String) -> String? { supportedCodes.contains(code) ? code : nil }
    public static var otherLanguages: [SpokenLanguage] {
        let indianCodes = Set(indian.map(\.code))
        return supportedCodes.subtracting(indianCodes).map { code in
            SpokenLanguage(name: Locale.current.localizedString(forLanguageCode: code) ?? code, code: code, dedicatedRecognition: true)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
