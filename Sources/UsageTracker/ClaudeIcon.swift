import AppKit

/// The little pixel-art Claude Code mascot, drawn in code so there's no asset to ship.
enum ClaudeIcon {
    static let terracotta = NSColor(srgbRed: 0.851, green: 0.467, blue: 0.341, alpha: 1)  // #D97757

    /// Each "#" is one pixel; the gaps in rows 2–3 are the eyes, rows 7–8 the legs.
    private static let sprite = [
        "..########..",
        "..########..",
        "..#.####.#..",
        "..#.####.#..",
        "############",
        "..########..",
        "..########..",
        "..#.#..#.#..",
        "..#.#..#.#..",
    ]

    static func image(size: CGFloat = 18, color: NSColor = terracotta) -> NSImage {
        let cols = CGFloat(sprite[0].count), rows = CGFloat(sprite.count)
        let px = size / cols
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            let originY = (size - rows * px) / 2
            // One path for all pixels so anti-aliasing doesn't leave seams between them.
            let path = NSBezierPath()
            for (r, line) in sprite.enumerated() {
                for (c, ch) in line.enumerated() where ch == "#" {
                    path.appendRect(NSRect(x: CGFloat(c) * px, y: originY + CGFloat(r) * px, width: px, height: px))
                }
            }
            color.setFill()
            path.fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
