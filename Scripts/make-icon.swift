import AppKit
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let s = CGFloat(size) / 1024
    NSColor(calibratedRed: 0.94, green: 0.95, blue: 0.92, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 60*s, y: 60*s, width: 904*s, height: 904*s), xRadius: 202*s, yRadius: 202*s).fill()
    NSColor(calibratedRed: 0.25, green: 0.40, blue: 0.33, alpha: 1).setFill()
    for (index, height) in [180, 330, 490, 330, 180].enumerated() {
        NSBezierPath(roundedRect: NSRect(x: CGFloat(242 + index * 112)*s, y: CGFloat(512-height/2)*s, width: 76*s, height: CGFloat(height)*s), xRadius: 38*s, yRadius: 38*s).fill()
    }
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let png = bitmap.representation(using: .png, properties: [:])!
    if size <= 512 { try png.write(to: destination.appendingPathComponent("icon_\(size)x\(size).png")) }
    if size >= 32 { try png.write(to: destination.appendingPathComponent("icon_\(size/2)x\(size/2)@2x.png")) }
}
