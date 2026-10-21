# UsageTracker

A tiny macOS menu bar app that shows your Claude Code usage: a little pixel Claude mascot plus today's estimated cost, with a panel showing more detail.

- **5-hour session ring:** usage against your limit (or your busiest past session), time until reset, burn rate and projected total
- **Today / 7 days / 30 days** cost and token totals
- **14-day chart** and an **active-hours heatmap**
- **Breakdown by project or model** (temporary folders hidden by default)
- **Notifications** for 80% / 100% of the session limit, window resets and a daily spend threshold
- **Launch at login**

Everything is read locally from Claude Code's transcripts in `~/.claude/projects`. Nothing leaves your Mac. Costs are estimates at Anthropic API list prices (see `Sources/UsageTracker/Pricing.swift`). Subscription plans are billed differently.

## Build

Requires macOS 14+ and the Swift toolchain (the Xcode Command Line Tools are enough).

```bash
./build.sh            # builds build/UsageTracker.app
./build.sh --install  # also copies it to /Applications and launches it
```

Debug flags: `UsageTracker --dump` prints the computed numbers, and `UsageTracker --render out.png` saves an image of the panel.
