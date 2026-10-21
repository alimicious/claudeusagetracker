import AppKit

/// The app's Finder/Launchpad icon: the pixel mascot on a dark macOS-style tile.
/// build.sh renders it with `UsageTracker --iconset <dir>` and packs it with iconutil,
/// so it always matches the menu bar sprite.
enum AppIcon {
    private static let top = NSColor(srgbRed: 0.20, green: 0.19, blue: 0.18, alpha: 1)
    private static let bottom = NSColor(srgbRed: 0.11, green: 0.105, blue: 0.10, alpha: 1)

    /// Writes the PNG sizes iconutil expects into an .iconset folder.
    static func writeIconset(to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
                try png(pixels: points * scale).write(to: dir.appendingPathComponent(name))
            }
        }
    }

    private static func png(pixels: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(size: CGFloat(pixels))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    /// Follows Apple's icon grid: an 824pt tile centered on a 1024pt canvas, with a soft drop shadow.
    private static func draw(size s: CGFloat) {
        let tile = NSRect(x: 0, y: 0, width: s, height: s).insetBy(dx: s * 100 / 1024, dy: s * 100 / 1024)
        let path = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.2237, yRadius: tile.width * 0.2237)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 0, height: -s * 10 / 1024)
        shadow.shadowBlurRadius = s * 20 / 1024
        shadow.shadowColor = NSColor(white: 0, alpha: 0.3)
        shadow.set()
        bottom.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(starting: top, ending: bottom)!.draw(in: path, angle: -90)

        let mascot = tile.width * 0.64
        ClaudeIcon.image(size: mascot, frame: .idle)
            .draw(in: NSRect(x: tile.midX - mascot / 2, y: tile.midY - mascot / 2, width: mascot, height: mascot))
    }
}
