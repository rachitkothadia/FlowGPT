import AppKit
import CryptoKit
import FlowCore
import Observation

@MainActor @Observable final class MacUpdater {
    private(set) var busy = false
    private(set) var message = "Check for a newer version of FlowGpt."
    private(set) var available: MacReleaseUpdate?
    @ObservationIgnored var onAvailable: ((MacReleaseUpdate) -> Void)?
    @ObservationIgnored private var automaticTask: Task<Void, Never>?
    func startAutomaticChecks(isDictating: @escaping @MainActor () -> Bool) {
        stopAutomaticChecks()
        automaticTask = Task { [weak self] in
            var nextCheck = Date().addingTimeInterval(10)
            var announced = Set<String>()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                guard let self else { return }
                guard !isDictating(), !busy else { continue }
                if Date() >= nextCheck {
                    nextCheck = Date().addingTimeInterval(6 * 60 * 60)
                    await check()
                }
                guard !Task.isCancelled, !isDictating(), let update = available,
                      !announced.contains(update.version), let onAvailable else { continue }
                announced.insert(update.version)
                onAvailable(update)
            }
        }
    }
    func stopAutomaticChecks() { automaticTask?.cancel(); automaticTask = nil }
    func check() async {
        guard !busy else { return }
        busy = true; available = nil; message = "Checking for updates…"
        defer { busy = false }
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/rachitkothadia/FlowGPT/releases?per_page=100")!)
            request.timeoutInterval = 20
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("FlowGpt-update-check", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 2_000_000 else { throw FlowError.network }
            let releases = try JSONDecoder().decode([PublishedRelease].self, from: data)
            #if arch(arm64)
            let architecture = "arm64"
            #else
            let architecture = "x86_64"
            #endif
            available = ReleaseUpdatePolicy.latestMac(releases, current: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2.0", architecture: architecture)
            message = available.map { "Version \($0.version) is available\($0.preview ? " (preview)" : "")." } ?? "You’re using the latest compatible version."
        } catch { message = "Couldn’t check for updates. Check your connection and try again." }
    }
    func downloadAndOpen() async {
        guard !busy, let update = available else { return }
        busy = true; message = "Downloading and verifying the update…"
        defer { busy = false }
        var temporary: URL?
        do {
            let (checksums, response) = try await URLSession.shared.data(from: update.checksum.browser_download_url)
            guard (response as? HTTPURLResponse)?.statusCode == 200, checksums.count <= 100_000,
                  let content = String(data: checksums, encoding: .utf8),
                  let expected = ReleaseUpdatePolicy.checksum(content, filename: update.installer.name) else { throw FlowError.malformedResponse }
            let (file, downloadResponse) = try await URLSession.shared.download(from: update.installer.browser_download_url)
            temporary = file
            guard (downloadResponse as? HTTPURLResponse)?.statusCode == 200,
                  (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize) == update.installer.size else { throw FlowError.malformedResponse }
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            var digest = SHA256()
            while let block = try handle.read(upToCount: 1_048_576), !block.isEmpty { digest.update(data: block) }
            let actual = digest.finalize().map { String(format: "%02x", $0) }.joined()
            guard actual == expected else { throw FlowError.malformedResponse }
            let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("FlowGPT/Updates", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(update.installer.name)
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.moveItem(at: file, to: destination)
            temporary = nil
            // Download provenance stays quarantined. Never bypass Gatekeeper or
            // reset permissions. macOS remains responsible for signature checks.
            let provenance = "0081;\(String(Int(Date().timeIntervalSince1970), radix: 16));FlowGpt;"
            let quarantined = provenance.withCString { value in destination.path.withCString { path in
                setxattr(path, "com.apple.quarantine", value, strlen(value), 0, 0)
            } }
            guard quarantined == 0 else { throw FlowError.storage }
            guard NSWorkspace.shared.open(destination) else { throw FlowError.storage }
            message = "Verified installer opened. Quit FlowGpt and replace it in Applications. Your history and connection stay saved."
        } catch { message = "Update could not be verified or opened. Nothing was installed. Try again or visit GitHub Releases." }
        if let temporary { try? FileManager.default.removeItem(at: temporary) }
    }
}
