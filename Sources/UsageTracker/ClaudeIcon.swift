import AppKit

/// The little pixel-art Claude Code mascot, drawn in code so there's no asset to ship.
enum ClaudeIcon {
    static let terracotta = NSColor(srgbRed: 0.851, green: 0.467, blue: 0.341, alpha: 1)  // #D97757

    enum Frame: Hashable, CaseIterable {
        case idle, blink, typeRest, typeLeft, typeRight
    }

    /// Pixel colors: "#" mascot, "L" laptop lid, "K" laptop base; "." is transparent.
    private static let palette: [Character: NSColor] = [
        "#": terracotta,
        "L": NSColor(white: 0.72, alpha: 1),
        "K": NSColor(white: 0.48, alpha: 1),
    ]

    /// The gaps in rows 2–3 are the eyes, rows 7–8 the legs.
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

    /// Sitting behind a mini laptop (the back of its lid faces us), both hands on the base.
    private static let typing = [
        "..########..",
        "..########..",
        "..#.####.#..",
        "..#.####.#..",
        "..########..",
        "..########..",
        "...LLLLLL...",
        "...LLLLLL...",
        ".##LLLLLL##.",
        "KKKKKKKKKKKK",
    ]

    private static let sprites: [Frame: [String]] = [
        .idle: idle,
        .blink: replacing(idle, [2: "..########..", 3: "..########.."]),
        .typeRest: typing,
        // One hand lifts off the keys while the other presses down.
        .typeLeft: replacing(typing, [7: ".##LLLLLL...", 8: "...LLLLLL##."]),
        .typeRight: replacing(typing, [7: "...LLLLLL##.", 8: ".##LLLLLL..."]),
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
            // One path per color so anti-aliasing doesn't leave seams between pixels.
            for (char, color) in palette {
                let path = NSBezierPath()
                for (r, line) in sprite.enumerated() {
                    for (c, ch) in line.enumerated() where ch == char {
                        path.appendRect(NSRect(x: CGFloat(c) * px, y: originY + CGFloat(r) * px, width: px, height: px))
                    }
                }
                color.setFill()
                path.fill()
            }
            return true
        }
        image.isTemplate = false
        cache[key] = image
        return image
    }
}
