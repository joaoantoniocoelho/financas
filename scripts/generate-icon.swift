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
    NSGradient(starting: NSColor(red: 0.08, green: 0.31, blue: 0.24, alpha: 1),
               ending: NSColor(red: 0.04, green: 0.16, blue: 0.14, alpha: 1))!.draw(in: background, angle: -60)
    NSColor(red: 0.76, green: 0.91, blue: 0.64, alpha: 1).setStroke()
    let ring = NSBezierPath()
    ring.appendArc(withCenter: NSPoint(x: 512, y: 512), radius: 240, startAngle: 90, endAngle: 360)
    ring.lineWidth = 54
    ring.lineCapStyle = .round
    ring.stroke()
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 425, y: 425))
    arrow.line(to: NSPoint(x: 660, y: 660))
    arrow.move(to: NSPoint(x: 490, y: 660))
    arrow.line(to: NSPoint(x: 660, y: 660))
    arrow.line(to: NSPoint(x: 660, y: 490))
    arrow.lineWidth = 54
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.stroke()
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
