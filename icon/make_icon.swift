// Regenerates icon/AppIcon.icns: swift icon/make_icon.swift && iconutil -c icns build/AppIcon.iconset -o icon/AppIcon.icns
import AppKit

func draw(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024) // all coordinates below are on a 1024 grid

    func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
    }

    // Background: Apple's 824pt icon tile with a soft shadow
    let tile = rounded(100, 100, 824, 824, 186)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    NSColor.black.setFill()
    tile.fill()
    ctx.restoreGState()
    NSGradient(starting: NSColor(calibratedRed: 0.36, green: 0.30, blue: 0.95, alpha: 1),
               ending: NSColor(calibratedRed: 0.10, green: 0.62, blue: 0.96, alpha: 1))!.draw(in: tile, angle: -60)

    // Three Spaces in a row, cut off by the tile edge, with the middle one in focus
    ctx.saveGState()
    tile.addClip()
    NSColor.white.withAlphaComponent(0.32).setFill()
    rounded(-10, 430, 260, 300, 44).fill()
    rounded(774, 430, 260, 300, 44).fill()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: NSColor.black.withAlphaComponent(0.28).cgColor)
    NSColor.white.setFill()
    rounded(290, 400, 444, 360, 52).fill()
    ctx.restoreGState()

    // Double-headed arrow: the swipe
    let arrow = NSBezierPath()
    arrow.lineWidth = 44
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 330, y: 262)); arrow.line(to: NSPoint(x: 694, y: 262))
    arrow.move(to: NSPoint(x: 400, y: 332)); arrow.line(to: NSPoint(x: 330, y: 262)); arrow.line(to: NSPoint(x: 400, y: 192))
    arrow.move(to: NSPoint(x: 624, y: 332)); arrow.line(to: NSPoint(x: 694, y: 262)); arrow.line(to: NSPoint(x: 624, y: 192))
    NSColor.white.setStroke()
    arrow.stroke()

    NSGraphicsContext.current = nil
    return rep.representation(using: .png, properties: [:])!
}

let dir = URL(fileURLWithPath: "build/AppIcon.iconset")
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try draw(size).write(to: dir.appendingPathComponent("icon_\(size)x\(size).png"))
    try draw(size * 2).write(to: dir.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
