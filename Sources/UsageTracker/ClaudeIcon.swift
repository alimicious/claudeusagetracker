import AppKit

/// The little pixel-art Claude Code mascot, drawn in code so there's no asset to ship.
enum ClaudeIcon {
    static let terracotta = NSColor(srgbRed: 0.851, green: 0.467, blue: 0.341, alpha: 1)  // #D97757

    enum Frame: Hashable {
        case idle, blink, walkA, walkB
    }

    /// Each "#" is one pixel; the gaps in rows 2–3 are the eyes, rows 7–8 the legs.
    private static let idle = [
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

    private static let sprites: [Frame: [String]] = [
        .idle: idle,
        .blink: replacing(idle, [2: "..########..", 3: "..########.."]),
        // Walking: alternate pairs of legs lift while the arms bob up and down.
        .walkA: replacing(idle, [8: "..#....#...."]),
        .walkB: replacing(idle, [3: "###.####.###", 4: "..########..", 8: "....#....#.."]),
    ]

    private static func replacing(_ rows: [String], _ changes: [Int: String]) -> [String] {
        rows.enumerated().map { changes[$0.offset] ?? $0.element }
    }

    private static var cache: [String: NSImage] = [:]

    static func image(size: CGFloat = 18, frame: Frame = .idle) -> NSImage {
        let key = "\(frame)-\(size)"
        if let cached = cache[key] { return cached }

        let sprite = sprites[frame]!
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
            terracotta.setFill()
            path.fill()
            return true
        }
        image.isTemplate = false
        cache[key] = image
        return image
    }
}
