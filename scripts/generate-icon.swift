import AppKit

// Run from the repository root: swift scripts/generate-icon.swift
// The icon is drawn from paths so every macOS size has a crisp source.
// iOS gets an opaque, full-bleed variant; the system applies its own corner mask.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent(".build/Financas.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(size: Int, fullBleed: Bool = false) throws -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: fullBleed ? 3 : 4, hasAlpha: !fullBleed,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let background = fullBleed
        ? NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024))
        : NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 220, yRadius: 220)
    NSGradient(starting: NSColor(red: 0.06, green: 0.27, blue: 0.20, alpha: 1),
               ending: NSColor(red: 0.02, green: 0.12, blue: 0.09, alpha: 1))!.draw(in: background, angle: -70)

    let mint = NSColor(red: 0.76, green: 0.91, blue: 0.64, alpha: 1)
    NSGraphicsContext.saveGraphicsState()
    background.addClip()
    // A soft light behind the mark and faint ledger rules, as in the splash.
    NSGradient(colors: [mint.withAlphaComponent(0.16), mint.withAlphaComponent(0)])!
        .draw(fromCenter: NSPoint(x: 530, y: 540), radius: 0, toCenter: NSPoint(x: 530, y: 540), radius: 380, options: [])
    NSColor.white.withAlphaComponent(0.045).setFill()
    for y in stride(from: 212, through: 812, by: 75) { NSBezierPath(rect: NSRect(x: 0, y: y, width: 1024, height: 2)).fill() }
    NSGraphicsContext.restoreGraphicsState()

    // The mark, from MarkGeometry (Sources/Financas/BrandViews.swift): a 100-unit artboard, y down.
    // Here the ring is 500 px across; small sizes get a heavier stroke so the lines stay visible.
    let unit: CGFloat = 500 / 68
    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: 512 + (x - 50) * unit, y: 512 - (y - 50) * unit) }
    let stroke = max(2.6 * unit, 1.6 * 1024 / CGFloat(size))
    mint.setStroke()
    let ring = NSBezierPath()
    ring.appendArc(withCenter: point(50, 50), radius: 34 * unit, startAngle: 90, endAngle: 360)
    ring.lineWidth = stroke
    ring.lineCapStyle = .round
    ring.stroke()
    let chart = NSBezierPath()
    chart.move(to: point(27, 64))
    for (x, y) in [(41.0, 50.0), (51.0, 58.0), (74.0, 26.0)] { chart.line(to: point(x, y)) }
    chart.lineWidth = stroke
    chart.lineCapStyle = .round
    chart.lineJoinStyle = .round
    chart.stroke()
    let tip = point(74, 26)
    if size >= 128 {
        let halo = 8.5 * unit
        mint.withAlphaComponent(0.4).setStroke()
        let ring = NSBezierPath(ovalIn: NSRect(x: tip.x - halo, y: tip.y - halo, width: halo * 2, height: halo * 2))
        ring.lineWidth = stroke * 0.4
        ring.stroke()
    }
    let dot = max(4.2 * unit, stroke * 1.4)
    mint.setFill()
    NSBezierPath(ovalIn: NSRect(x: tip.x - dot, y: tip.y - dot, width: dot * 2, height: dot * 2)).fill()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try render(size: size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size: size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try render(size: 1024).write(to: root.appendingPathComponent("Resources/AppIcon.png"))
try render(size: 1024, fullBleed: true).write(to: root.appendingPathComponent("iOS/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"))
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("Não foi possível gerar o ícone.") }
