import AppKit
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let image = NSImage(size: NSSize(width: 640, height: 420))
image.lockFocus()
NSColor(calibratedRed: 0.94, green: 0.96, blue: 0.93, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 640, height: 420)).fill()
func text(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor, bold: Bool = false) {
    let font = bold ? NSFont.systemFont(ofSize: size, weight: .bold) : NSFont.systemFont(ofSize: size)
    (value as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: font, .foregroundColor: color])
}
let moss = NSColor(calibratedRed: 0.25, green: 0.40, blue: 0.33, alpha: 1)
text("Make room for your flow.", x: 42, y: 348, size: 30, color: moss, bold: true)
text("Drag Flow into Applications to install.", x: 44, y: 315, size: 16, color: .darkGray)
NSColor.white.withAlphaComponent(0.65).setFill()
for x: CGFloat in [78, 428] { NSBezierPath(roundedRect: NSRect(x: x, y: 114, width: 136, height: 148), xRadius: 28, yRadius: 28).fill() }
moss.withAlphaComponent(0.6).setStroke()
let arrow = NSBezierPath(); arrow.lineWidth = 3
arrow.move(to: NSPoint(x: 250, y: 195)); arrow.line(to: NSPoint(x: 390, y: 195)); arrow.move(to: NSPoint(x: 377, y: 207)); arrow.line(to: NSPoint(x: 390, y: 195)); arrow.line(to: NSPoint(x: 377, y: 183)); arrow.stroke()
text("drag & drop", x: 275, y: 219, size: 13, color: moss)
text("Your voice. Your words.", x: 44, y: 43, size: 15, color: moss, bold: true)
text("Then open Flow from Applications to get started.", x: 44, y: 22, size: 12, color: .darkGray)
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: output)
