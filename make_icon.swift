// Draws AppIcon.icns: `swift make_icon.swift`. Only needed when the icon changes; the .icns is checked in.
import AppKit

func symbol(_ name: String, size: CGFloat, color: NSColor) -> NSImage {
    let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(cfg)!
}

func draw(_ image: NSImage, centredAt c: CGPoint) {
    let s = image.size
    image.draw(in: CGRect(x: c.x - s.width / 2, y: c.y - s.height / 2, width: s.width, height: s.height))
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)   // draw on a 1024 grid

    // The standard macOS tile: 824 square in a 1024 canvas, with a soft shadow under it.
    let tile = NSBezierPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    NSColor.black.setFill()
    tile.fill()
    ctx.restoreGState()
    NSGradient(starting: NSColor(red: 0.33, green: 0.38, blue: 0.47, alpha: 1),
               ending: NSColor(red: 0.13, green: 0.15, blue: 0.20, alpha: 1))!.draw(in: tile, angle: -90)

    draw(symbol("keyboard.fill", size: 400, color: .white), centredAt: CGPoint(x: 512, y: 545))

    // The lock sits on a badge that cuts into the keyboard's corner.
    let badge = CGRect(x: 560, y: 190, width: 290, height: 290)
    NSColor(red: 0.13, green: 0.15, blue: 0.20, alpha: 1).setFill()
    NSBezierPath(ovalIn: badge.insetBy(dx: -22, dy: -22)).fill()
    NSColor(red: 1.0, green: 0.62, blue: 0.04, alpha: 1).setFill()
    NSBezierPath(ovalIn: badge).fill()
    draw(symbol("lock.fill", size: 150, color: .white), centredAt: CGPoint(x: badge.midX, y: badge.midY))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let set = "AppIcon.iconset"
try? fm.removeItem(atPath: set)
try fm.createDirectory(atPath: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: URL(fileURLWithPath: "\(set)/icon_\(base)x\(base).png"))
    try render(base * 2).write(to: URL(fileURLWithPath: "\(set)/icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set, "-o", "AppIcon.icns"]
try p.run()
p.waitUntilExit()
try? fm.removeItem(atPath: set)
exit(p.terminationStatus)
