import Foundation
import Testing
@testable import FlowCore

struct Flow11Tests {
    @Test func conservativePresentationPreservesMixedSpeechAndRepetition() {
        for text in [
            "ओके so मेरे MacBook में storage बहुत कम है. um मैं मैं delete नहीं करना चाहता.",
            "अरे Brajesh, तू तू मेरे लिए काम कर. But अभी मुझे नींद आ रही है।",
            "मला one task आहे, तू try again क्लिक कर, आणि मला कळव.",
            "Then I pressed 'Try again' but it still failed. Failed. Failed!",
            "my maby is not my baby; garam masala is not hot sauce.",
            "January 1. That was a date, 2. This is ordinary speech.",
            "1. keep `x += 1` 2. keep code", "1. https://example.com/a 2. /tmp/example",
            "He said \"um\". Keep it in the quotation.", "1. quote \"2. stays exact\"", "အင်္ဂလိပ် hello বাংলা తెలుగు தமிழ் ગુજરાતી"
        ] { #expect(ConservativeFormatting.format(text) == text) }
    }
    @Test func onlyExplicitNumberingCanGainNewlinesWithoutChangingWords() {
        #expect(ConservativeFormatting.format("Three tasks: 1. Shop 2. Call Dad 3. Fill the form") == "Three tasks:\n1. Shop\n2. Call Dad\n3. Fill the form")
        #expect(ConservativeFormatting.format("तीन काम: 1. shopping 2. form भर 3. Dad ला call कर") == "तीन काम:\n1. shopping\n2. form भर\n3. Dad ला call कर")
        #expect(ConservativeFormatting.format("go shopping and call dad then fill a passport form") == "go shopping and call dad then fill a passport form")
        #expect(ConservativeFormatting.format("1. start 3. gap") == "1. start 3. gap")
        #expect(ConservativeFormatting.format("version 1.5, version 2.7") == "version 1.5, version 2.7")
        let unlimited = (1...200).map { "\($0). task \($0)" }.joined(separator: " ")
        #expect(ConservativeFormatting.format(unlimited).split(separator: "\n").count == 200)
        #expect(ConservativeFormatting.format(unlimited).split(whereSeparator: \.isWhitespace) == unlimited.split(whereSeparator: \.isWhitespace))
    }
    @Test func completionRequiresProviderSignalAndStableFullText() {
        var policy = TranscriptCompletion()
        #expect(policy.observe(text: "Hello", ready: false, transcribing: true, recording: false, at: 0) == nil)
        #expect(policy.observe(text: "Hello", ready: true, transcribing: true, recording: false, at: 1) == nil)
        #expect(policy.observe(text: "Hello", ready: true, transcribing: false, recording: true, at: 2) == nil)
        #expect(policy.observe(text: "Hello", ready: true, transcribing: false, recording: false, at: 3) == nil)
        #expect(policy.observe(text: "Hello testing", ready: true, transcribing: false, recording: false, at: 3.19) == nil)
        #expect(policy.observe(text: "Hello testing", ready: true, transcribing: false, recording: false, at: 3.3) == nil)
        #expect(policy.observe(text: "Hello testing", ready: true, transcribing: false, recording: false, at: 3.4) == "Hello testing")
        #expect(policy.observe(text: "", ready: true, transcribing: false, recording: false, at: 7) == nil)
    }
    @Test func nativeRichEditorDoesNotNeedWritableWholeDocument() {
        #expect(InsertionSafety.editableCapability(explicitEditable: nil, explicitReadOnly: nil, enabled: true,
            standardTextRole: false, writableValue: false, writableSelectedText: false, hasSelectedRange: true, supportsTextRange: true))
        for blocked in [0, 1, 2] {
            #expect(!InsertionSafety.editableCapability(explicitEditable: blocked == 0 ? false : nil,
                explicitReadOnly: blocked == 1 ? true : nil, enabled: blocked == 2 ? false : true,
                standardTextRole: true, writableValue: true, writableSelectedText: true, hasSelectedRange: true, supportsTextRange: true))
        }
        #expect(!InsertionSafety.editableCapability(explicitEditable: nil, explicitReadOnly: nil, enabled: true,
            standardTextRole: false, writableValue: false, writableSelectedText: false, hasSelectedRange: false, supportsTextRange: true))
        #expect(!InsertionSafety.editableCapability(explicitEditable: nil, explicitReadOnly: nil, enabled: false,
            standardTextRole: true, writableValue: false, writableSelectedText: false, hasSelectedRange: true, supportsTextRange: true, supportsRangeReplacement: true))
        #expect(!InsertionSafety.editableCapability(explicitEditable: nil, explicitReadOnly: true, enabled: false,
            standardTextRole: true, writableValue: true, writableSelectedText: true, hasSelectedRange: true, supportsTextRange: true, supportsRangeReplacement: true))
    }
    private func asset(_ name: String, size: Int = 100) -> ReleaseAsset {
        .init(name: name, url: URL(string: "https://github.com/rachitkothadia/FlowGPT/releases/download/v2.0.0/" + name)!, size: size)
    }
    @Test func updateSelectsLatestCompatibleInstallerWithPublishedChecksum() {
        let releases = [PublishedRelease(draft: false, prerelease: false, assets: [asset("FlowGpt-1.1.0-arm64.dmg"), asset("SHA256SUMS.txt")]),
            PublishedRelease(draft: false, prerelease: true, assets: [asset("FlowGpt-2.0.0-universal.dmg"), asset("SHA256SUMS.txt")]),
            PublishedRelease(draft: true, prerelease: false, assets: [asset("FlowGpt-3.0.0-arm64.dmg"), asset("SHA256SUMS.txt")])]
        #expect(ReleaseUpdatePolicy.latestMac(releases, current: "1.0.3", architecture: "arm64")?.version == "2.0.0")
        #expect(ReleaseUpdatePolicy.latestMac(releases, current: "1.1.0", architecture: "x86_64")?.preview == true)
        #expect(ReleaseUpdatePolicy.latestMac(releases, current: "2.0.0", architecture: "arm64") == nil)
        #expect(ReleaseUpdatePolicy.latestMac([.init(draft: false, prerelease: false, assets: [asset("FlowGpt-4.0.0-arm64.dmg")])], current: "1.1.0", architecture: "arm64") == nil)
        #expect(ReleaseUpdatePolicy.latestMac([.init(draft: false, prerelease: false, assets: [asset("FlowGPT-4.0.0-Windows-x64-Setup.exe"), asset("SHA256SUMS.txt")])], current: "1.1.0", architecture: "arm64") == nil)
    }
    @Test func updateTrustAndChecksumFailClosed() {
        for url in ["http://github.com/rachitkothadia/FlowGPT/releases/download/v1/a.dmg",
            "https://github.com/other/repo/releases/download/v1/a.dmg", "https://github.com.evil.example/rachitkothadia/FlowGPT/releases/download/v1/a.dmg",
            "https://user@github.com/rachitkothadia/FlowGPT/releases/download/v1/a.dmg"] {
            #expect(!ReleaseUpdatePolicy.trustedAsset(URL(string: url)!))
        }
        let hash = String(repeating: "a", count: 64), filename = "FlowGpt-1.1.0-arm64.dmg"
        #expect(ReleaseUpdatePolicy.checksum(hash + "  " + filename, filename: filename) == hash)
        #expect(ReleaseUpdatePolicy.checksum(hash + " *" + filename, filename: filename) == hash)
        #expect(ReleaseUpdatePolicy.checksum(hash + " /tmp/" + filename, filename: filename) == nil)
        #expect(ReleaseUpdatePolicy.checksum(hash + "  " + filename + "\n" + hash + "  " + filename, filename: filename) == nil)
        #expect(ReleaseUpdatePolicy.checksum("bad  " + filename, filename: filename) == nil)
        #expect(ReleaseVersion("1.1.0")! > ReleaseVersion("1.0.99")!)
        #expect(ReleaseVersion("1.1") == nil && ReleaseVersion("1.1.0-beta") == nil)
    }
}
