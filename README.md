# UsageTracker

A tiny macOS menu bar app that shows your Claude Code usage: a little pixel mascot (who types on a laptop while Claude works) plus today's estimated cost, with a panel showing more detail.

> **Unofficial fan project.** Not affiliated with or endorsed by Anthropic. "Claude" and the Claude Code mascot belong to Anthropic.

- **5-hour session ring:** usage against your limit (or your busiest past session), time until reset, burn rate and projected total
- **Today / 7 days / 30 days** totals, shown as cost, tokens or a theoretical water estimate
- **14-day chart** and an **active-hours heatmap**
- **Breakdown by project or model** (temporary folders hidden by default)
- **Notifications** for 80% / 100% of the session limit, window resets and a daily spend threshold
- **Launch at login**
- **Liquid Glass** styling on macOS 26 and later

## About the water estimate

Choose **Water** under *Show amounts as* to see a theoretical estimate, in litres, of the water used to serve your requests: data-center cooling plus water used to generate the electricity (training isn't included). Anthropic doesn't publish energy or water data, so it's derived from published estimates for frontier-model inference:

| Token type | Energy | Water |
|---|---|---|
| Output | ~2 Wh per 1k tokens | 7 mL per 1k tokens |
| Input and cache writes | ~0.4 Wh per 1k tokens | 1.4 mL per 1k tokens |
| Cache reads | ~0.04 Wh per 1k tokens | 0.14 mL per 1k tokens |

That assumes about 3.5 mL of water per Wh: around 0.5 L/kWh for on-site cooling (Google, Microsoft and AWS report 0.15–1.15) plus about 3 L/kWh for US electricity generation. Real figures could be several times lower or higher. Sources: [Epoch AI (2025)](https://epoch.ai/gradient-updates/how-much-energy-does-chatgpt-use), [Oviedo et al. (2025)](https://arxiv.org/abs/2509.20241), [Google (2025)](https://cloud.google.com/blog/products/infrastructure/measuring-the-environmental-impact-of-ai-inference), [Li et al., "Making AI Less Thirsty"](https://arxiv.org/abs/2304.03271), [Mistral (2025)](https://mistral.ai/news/our-contribution-to-a-global-environmental-standard-for-ai).

Everything is read locally from Claude Code's transcripts in `~/.claude/projects`. The app never connects to the internet. Costs are estimates at Anthropic API list prices (see `Sources/UsageTracker/Pricing.swift`). Subscription plans are billed differently.

## Install

Requires macOS 14 or later and [Claude Code](https://claude.com/claude-code). Runs on Apple Silicon and Intel Macs.

1. Download the latest **UsageTracker zip** from the [Releases page](https://github.com/alimicious/claudeusagetracker/releases/latest) and double-click it to unzip.
2. Drag **UsageTracker** into your **Applications** folder and open it.
3. macOS will say it can't verify the app, because it isn't notarized by Apple. Click **Done**, then open **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. You only need to do this once.

Then look for the mascot in your menu bar and click it. To start it automatically, open settings (the gear) and turn on **Launch at login**.

## Build from source

Requires the Swift toolchain (the Xcode Command Line Tools are enough).

```bash
./build.sh                       # builds build/UsageTracker.app for this Mac
./build.sh --install             # also copies it to /Applications and launches it
./build.sh --universal           # builds for both Apple Silicon and Intel
./release.sh                     # builds a universal zip and publishes a GitHub release for ./VERSION
```

Debug flags: `UsageTracker --dump` prints the computed numbers, and `UsageTracker --render out.png` saves an image of the panel.
