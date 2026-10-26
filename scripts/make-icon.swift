import AppKit

// Renders the CmdTab app icon (rounded square, gradient, two stacked windows, ⌘⇥ glyph) into an .iconset.
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(_ px: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: px, height: px))
    img.lockFocus()
    let s = px / 1024
    let inset = 60 * s
    let rect = NSRect(x: inset, y: inset, width: px - 2 * inset, height: px - 2 * inset)
    let bg = NSBezierPath(roundedRect: rect, xRadius: 220 * s, yRadius: 220 * s)
    NSGradient(colors: [NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.36, alpha: 1),
                        NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.16, alpha: 1)])!
        .draw(in: bg, angle: -70)

    // Back window
    let back = NSBezierPath(roundedRect: NSRect(x: 300 * s, y: 420 * s, width: 520 * s, height: 340 * s), xRadius: 40 * s, yRadius: 40 * s)
    NSColor.white.withAlphaComponent(0.22).setFill(); back.fill()
    // Front window
    let front = NSBezierPath(roundedRect: NSRect(x: 200 * s, y: 300 * s, width: 520 * s, height: 340 * s), xRadius: 40 * s, yRadius: 40 * s)
    NSColor.white.withAlphaComponent(0.92).setFill(); front.fill()
    let bar = NSBezierPath(roundedRect: NSRect(x: 200 * s, y: 570 * s, width: 520 * s, height: 70 * s), xRadius: 0, yRadius: 0)
    NSColor(calibratedRed: 0.85, green: 0.87, blue: 0.92, alpha: 1).setFill(); bar.fill()
    for (i, c) in [NSColor.systemRed, NSColor.systemYellow, NSColor.systemGreen].enumerated() {
        c.setFill()
        NSBezierPath(ovalIn: NSRect(x: (235 + CGFloat(i) * 48) * s, y: 588 * s, width: 34 * s, height: 34 * s)).fill()
    }

    let text = "⌘⇥" as NSString
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 150 * s, weight: .bold),
        .foregroundColor: NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.3, alpha: 1),
    ]
    let size = text.size(withAttributes: attrs)
    text.draw(at: NSPoint(x: 460 * s - size.width / 2, y: 440 * s - size.height / 2), withAttributes: attrs)
    img.unlockFocus()
    return img
}

func write(_ img: NSImage, _ px: Int, _ name: String) {
    guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return }
    rep.size = NSSize(width: px, height: px)
    guard let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: out).appendingPathComponent(name))
}

for (size, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let px = size * scale
    let suffix = scale == 2 ? "@2x" : ""
    write(render(CGFloat(px)), px, "icon_\(size)x\(size)\(suffix).png")
}
print("wrote \(out)")
