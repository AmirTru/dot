import AppKit

// Draws the app icon: the menu bar glyph (dot on a text line) in color on a light macOS tile.
func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    let tile = NSBezierPath(roundedRect: CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s), xRadius: 185 * s, yRadius: 185 * s)
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 18 * s
    shadow.shadowOffset = CGSize(width: 0, height: -8 * s)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.white.setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(white: 1, alpha: 1), ending: NSColor(white: 0.9, alpha: 1))!.draw(in: tile, angle: -90)

    // Glyph grid is the 18 x 14 menu bar icon, scaled up and centered.
    let k = 34 * s, ox = 512 * s - 9 * k, oy = 512 * s - 8.25 * k
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: ox + x * k, y: oy + y * k, width: w * k, height: h * k) }
    let gray = NSGradient(starting: NSColor(srgbRed: 0.62, green: 0.63, blue: 0.66, alpha: 1), ending: NSColor(srgbRed: 0.50, green: 0.51, blue: 0.54, alpha: 1))!
    gray.draw(in: NSBezierPath(roundedRect: r(8, 9.2, 9, 2), xRadius: k, yRadius: k), angle: -90)
    gray.draw(in: NSBezierPath(roundedRect: r(1, 3, 16, 2), xRadius: k, yRadius: k), angle: -90)
    let green = NSGradient(starting: NSColor(srgbRed: 0.40, green: 0.86, blue: 0.47, alpha: 1), ending: NSColor(srgbRed: 0.16, green: 0.70, blue: 0.31, alpha: 1))!
    green.draw(in: NSBezierPath(ovalIn: r(1, 8.5, 5, 5)), angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let set = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: set.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: set.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
