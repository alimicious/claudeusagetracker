import Foundation

/// A theoretical estimate of the water used to serve Claude Code requests: inference only,
/// counting data-center cooling plus the water used to generate the electricity.
///
/// Anthropic publishes no energy or water data, so this uses published estimates for
/// frontier-model inference (Epoch AI 2025, Oviedo et al. 2025) of roughly 2 Wh per 1k output
/// tokens, 0.4 Wh per 1k input tokens and 0.04 Wh per 1k cache-read tokens (cache reads skip
/// most of the compute), at about 3.5 mL of water per Wh (on-site cooling ~0.5 L/kWh, as in
/// Google/Microsoft/AWS reports, plus ~3 L/kWh for US electricity generation, as in Li et al.
/// 2023). Real figures could plausibly be several times lower or higher.
enum Water {
    /// Millilitres per 1,000 tokens of each kind.
    static let outputPer1k = 7.0
    static let inputPer1k = 1.4       // uncached input and cache writes
    static let cacheReadPer1k = 0.14

    static let explanation = """
        Theoretical estimate of the water used to serve your requests: data-center cooling plus \
        water used to generate the electricity. Anthropic doesn't publish energy or water data, \
        so this uses published estimates for frontier models: about 2 Wh per 1,000 output tokens, \
        0.4 Wh per 1,000 input tokens and 0.04 Wh per 1,000 cached tokens, at about 3.5 mL of \
        water per Wh. Real figures could be several times lower or higher. Training isn't included.
        """

    static func liters(_ t: Totals) -> Double {
        let millilitres = Double(t.output) * outputPer1k
            + Double(t.input + t.cacheWrite) * inputPer1k
            + Double(t.cacheRead) * cacheReadPer1k
        return millilitres / 1_000_000  // per-1k rates → mL, then mL → L
    }

    static func format(_ liters: Double) -> String {
        switch liters {
        case ..<1: return "\(Int((liters * 1000).rounded())) mL"
        case ..<100: return String(format: "%.1f L", liters)
        default: return String(format: "%.0f L", liters)
        }
    }
}
