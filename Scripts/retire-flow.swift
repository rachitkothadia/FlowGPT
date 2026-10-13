import Foundation

// Explicit old build manifest; preserve the source tree, website storage,
// transcript history, NLP cache, and the replacement FlowGpt package.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let oldApps = [URL(fileURLWithPath: "/Applications/Flow.app")] + [
    "release/Flow.app", "release/Flow Glass Preview.app",
    "release/browser-bridge/Flow-19391.app", "release/browser-bridge/Flow-20154.app",
    "release/browser-bridge/Flow-21074.app", "release/browser-bridge/Flow-2487.app",
    "release/browser-bridge/Flow-28153.app"
].map { root.appendingPathComponent($0) }
let fm = FileManager.default
for app in oldApps where fm.fileExists(atPath: app.path) {
    let info = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
    let plist = try PropertyListSerialization.propertyList(from: info, format: nil) as? [String: Any]
    guard let id = plist?["CFBundleIdentifier"] as? String,
          ["in.vardaan.flow", "in.vardaan.flow.panelpreview"].contains(id) else {
        throw NSError(domain: "FlowGptCleanup", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unrelated app rejected: \(app.path)"])
    }
    try fm.trashItem(at: app, resultingItemURL: nil)
    print("Retired: \(app.path)")
}
for name in ["Flow-4.0.2-arm64.dmg", "Flow-5.0.0-browser-prototype-arm64.dmg"] {
    let file = root.appendingPathComponent(name)
    if fm.fileExists(atPath: file.path) { try fm.trashItem(at: file, resultingItemURL: nil); print("Retired: \(file.path)") }
}
