import Foundation

public struct ReleaseVersion: Comparable, Equatable, Sendable {
    public let components: [Int]
    public init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              parts.allSatisfy({ Int($0) != nil }) else { return nil }
        components = parts.compactMap { Int($0) }
    }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.components.lexicographicallyPrecedes(rhs.components) }
}

public struct ReleaseAsset: Decodable, Sendable {
    public let name: String
    public let browser_download_url: URL
    public let size: Int
    public init(name: String, url: URL, size: Int) { self.name = name; browser_download_url = url; self.size = size }
}
public struct PublishedRelease: Decodable, Sendable {
    public let draft: Bool
    public let prerelease: Bool
    public let assets: [ReleaseAsset]
    public init(draft: Bool, prerelease: Bool, assets: [ReleaseAsset]) { self.draft = draft; self.prerelease = prerelease; self.assets = assets }
}
public struct MacReleaseUpdate: Sendable {
    public let version: String
    public let installer: ReleaseAsset
    public let checksum: ReleaseAsset
    public let preview: Bool
}
public enum ReleaseUpdatePolicy {
    public static func trustedAsset(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "github.com" && url.user == nil && url.password == nil
            && url.path.hasPrefix("/rachitkothadia/FlowGPT/releases/download/")
            && url.query == nil && url.fragment == nil
    }
    public static func latestMac(_ releases: [PublishedRelease], current: String, architecture: String) -> MacReleaseUpdate? {
        guard let currentVersion = ReleaseVersion(current), ["arm64", "x86_64"].contains(architecture) else { return nil }
        var best: MacReleaseUpdate?
        for release in releases where !release.draft {
            for asset in release.assets {
                let parts = asset.name.split(separator: "-")
                guard parts.count == 3, parts[0] == "FlowGpt", let version = ReleaseVersion(String(parts[1])),
                      version > currentVersion,
                      [architecture + ".dmg", "universal.dmg"].contains(String(parts[2])),
                      asset.size > 0, asset.size <= 250_000_000, trustedAsset(asset.browser_download_url),
                      let checksum = release.assets.first(where: { $0.name == "SHA256SUMS.txt" && $0.size > 0 && $0.size <= 100_000 && trustedAsset($0.browser_download_url) }) else { continue }
                if let bestVersion = best.flatMap({ ReleaseVersion($0.version) }), version < bestVersion { continue }
                // Prefer universal on a same-version tie.
                if best?.version == String(parts[1]), best?.installer.name.hasSuffix("universal.dmg") == true { continue }
                best = MacReleaseUpdate(version: String(parts[1]), installer: asset, checksum: checksum, preview: release.prerelease)
            }
        }
        return best
    }
    public static func checksum(_ text: String, filename: String) -> String? {
        guard !filename.contains("/"), !filename.contains("\\") else { return nil }
        let matches = text.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard parts.count == 2 else { return nil }
            let hash = String(parts[0]), rawName = String(parts[1]).trimmingCharacters(in: .whitespaces)
            let name = rawName.hasPrefix("*") ? String(rawName.dropFirst()) : rawName
            guard name == filename, hash.count == 64, hash.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
            return hash.lowercased()
        }
        return matches.count == 1 ? matches[0] : nil
    }
}
