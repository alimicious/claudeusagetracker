import Foundation

/// Per-million-token API list prices (USD). Used to estimate what your usage
/// would cost at API rates — subscription plans are billed differently.
struct ModelPrice {
    let input: Double
    let output: Double
    let cacheRead: Double
    var cacheWrite5m: Double { input * 1.25 }
    var cacheWrite1h: Double { input * 2.0 }
}

enum Pricing {
    /// Ordered most-specific first; the first substring match wins.
    private static let table: [(match: String, price: ModelPrice)] = [
        ("fable-5-1",  ModelPrice(input: 10,   output: 50,   cacheRead: 0.25)),
        ("mythos-5-1", ModelPrice(input: 10,   output: 50,   cacheRead: 0.25)),
        ("fable-5",    ModelPrice(input: 10,   output: 50,   cacheRead: 1.00)),
        ("mythos",     ModelPrice(input: 10,   output: 50,   cacheRead: 1.00)),
        ("opus-5-5",   ModelPrice(input: 4,    output: 20,   cacheRead: 0.20)),
        ("opus-5",     ModelPrice(input: 5,    output: 25,   cacheRead: 0.50)),
        ("opus-4-5",   ModelPrice(input: 5,    output: 25,   cacheRead: 0.50)),
        ("opus-4-6",   ModelPrice(input: 5,    output: 25,   cacheRead: 0.50)),
        ("opus-4-7",   ModelPrice(input: 5,    output: 25,   cacheRead: 0.50)),
        ("opus-4-8",   ModelPrice(input: 5,    output: 25,   cacheRead: 0.50)),
        ("opus-4",     ModelPrice(input: 15,   output: 75,   cacheRead: 1.50)),
        ("sonnet-5",   ModelPrice(input: 2,    output: 10,   cacheRead: 0.20)),
        ("sonnet-4",   ModelPrice(input: 3,    output: 15,   cacheRead: 0.30)),
        ("haiku-5",    ModelPrice(input: 0.10, output: 0.50, cacheRead: 0.01)),
        ("haiku-4",    ModelPrice(input: 1,    output: 5,    cacheRead: 0.10)),
    ]

    static func price(for model: String) -> ModelPrice? {
        table.first { model.contains($0.match) }?.price
    }

    /// "claude-opus-5-5" → "Opus 5.5", "claude-sonnet-4-5-20250929" → "Sonnet 4.5"
    static func displayName(for model: String) -> String {
        var parts = model.split(separator: "-").map(String.init)
        if parts.first == "claude" { parts.removeFirst() }
        parts.removeAll { $0.count == 8 && Int($0) != nil }
        guard let family = parts.first else { return model }
        let version = parts.dropFirst().joined(separator: ".")
        return version.isEmpty ? family.capitalized : "\(family.capitalized) \(version)"
    }
}
