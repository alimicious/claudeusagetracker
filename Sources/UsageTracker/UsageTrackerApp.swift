import ServiceManagement
import SwiftUI
import UserNotifications

enum LabelMode: String, CaseIterable, Identifiable {
    case todayCost = "Today's cost"
    case todayTokens = "Today's tokens"
    case session = "5-hour session"
    case iconOnly = "Icon only"
    var id: String { rawValue }
}

/// What the panel's numbers are shown in. The session ring's % stays cost-based either way,
/// since plan limits track compute cost rather than raw token counts.
enum DisplayUnit: String, CaseIterable, Identifiable {
    case cost = "Cost"
    case tokens = "Tokens"
    var id: String { rawValue }

    func value(_ t: Totals) -> Double { self == .cost ? t.cost : Double(t.tokens) }
    func format(_ v: Double) -> String { self == .cost ? Format.cost(v) : Format.tokens(Int(v)) }
    func format(_ t: Totals) -> String { format(value(t)) }
    /// The other unit, for secondary lines.
    func secondary(_ t: Totals) -> String { self == .cost ? "\(Format.tokens(t.tokens)) tok" : Format.cost(t.cost) }
}

/// UserDefaults keys shared between the store and @AppStorage in the views.
enum Prefs {
    static let sessionLimit = "sessionLimit"      // Double, 0 = auto
    static let notifications = "notifications"    // Bool
    static let dailyAlert = "dailyAlert"          // Double, 0 = off
    static let knownReset = "knownReset"          // Double (epoch), a reset time copied from Claude's usage page
    static let limitMatchedAt = "limitMatchedAt"  // Double (epoch), when sessionLimit was matched to Claude's %
}

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot = UsageSnapshot()
    @Published private(set) var isLoading = false
    @Published var showSettings = false
    /// Draft values for the "Match Claude's usage page" form.
    @Published var matchPercent = 0.0
    @Published var matchReset = Date()
    @Published private(set) var matchMessage: String?
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    let mascot = MascotAnimator()
    private let scanner = LogScanner()
    private var hasLoaded = false

    /// Claude Code counts as working if it logged a response in the last 90 seconds.
    private var isWorking: Bool {
        snapshot.activeBlock.map { Date().timeIntervalSince($0.lastActivity) < 90 } ?? false
    }

    /// A static store for rendering the panel without a menu bar (see `--render`).
    init(preview: UsageSnapshot) {
        snapshot = preview
    }

    init() {
        Task {
            while !Task.isCancelled {
                await refresh()
                // Check more often while Claude is working so the mascot reacts quickly.
                try? await Task.sleep(for: .seconds(isWorking ? 10 : 30))
            }
        }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        let previous = snapshot
        snapshot = await scanner.snapshot(knownReset: knownReset)
        if hasLoaded { sendAlerts(previous: previous, current: snapshot) }
        hasLoaded = true
        isLoading = false
        mascot.setWorking(isWorking)
    }

    private var knownReset: Date? {
        let t = UserDefaults.standard.double(forKey: Prefs.knownReset)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    // MARK: - Matching Claude's usage page

    /// Fills the form with the current estimate, so only what differs needs changing.
    func prepareMatchForm() {
        matchReset = snapshot.activeBlock?.end ?? Date().addingTimeInterval(SessionBlock.length)
        matchPercent = 0
        matchMessage = nil
    }

    /// Pins the session window to Claude's reset time and, given Claude's "% used", works out
    /// the session limit that this Mac's Claude Code usage corresponds to.
    func matchClaude() async {
        let reset = Self.nextOccurrence(ofTimeIn: matchReset)
        guard reset.timeIntervalSinceNow <= SessionBlock.length else {
            matchMessage = "Claude's reset time should be within the next 5 hours."
            return
        }
        let defaults = UserDefaults.standard
        defaults.set(reset.timeIntervalSince1970, forKey: Prefs.knownReset)
        snapshot = await scanner.snapshot(knownReset: reset)

        guard matchPercent > 0 else {
            matchMessage = "Reset time matched."
            return
        }
        guard matchPercent <= 100, let block = snapshot.activeBlock, block.totals.cost > 0 else {
            matchMessage = "Reset time matched. No Claude Code usage in this window yet, so the % can't be matched."
            return
        }
        let limit = block.totals.cost / (matchPercent / 100)
        defaults.set(limit, forKey: Prefs.sessionLimit)
        defaults.set(Date().timeIntervalSince1970, forKey: Prefs.limitMatchedAt)
        matchMessage = "Matched: \(Format.cost(block.totals.cost)) here = \(Int(matchPercent))%, so your limit is about \(Format.cost(limit))."
        objectWillChange.send()
    }

    /// Claude shows only a time of day; take its next occurrence from now.
    static func nextOccurrence(ofTimeIn date: Date, after now: Date = Date()) -> Date {
        let cal = Calendar.current
        let time = cal.dateComponents([.hour, .minute], from: date)
        return cal.nextDate(after: now, matching: time, matchingPolicy: .nextTime) ?? date
    }

    func setLaunchAtLogin(_ on: Bool) {
        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setNotifications(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Prefs.notifications)
        objectWillChange.send()
        if on { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } }
    }

    // MARK: - Alerts

    private func sendAlerts(previous: UsageSnapshot, current: UsageSnapshot) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Prefs.notifications) else { return }

        // Session crossing 80% / 100% of the limit, once per level per session.
        if let b = current.activeBlock, let limit = current.limit(custom: defaults.double(forKey: Prefs.sessionLimit)) {
            let level = [1.0, 0.8].first { b.totals.cost / limit.cost >= $0 }
            let blockKey = b.start.timeIntervalSince1970
            let alerted = defaults.double(forKey: "alertedBlock") == blockKey ? defaults.double(forKey: "alertedLevel") : 0
            if let level, level > alerted {
                defaults.set(blockKey, forKey: "alertedBlock")
                defaults.set(level, forKey: "alertedLevel")
                notify(level >= 1 ? "You've reached your session limit" : "80% of your session limit used",
                       "\(Format.cost(b.totals.cost)) so far. Resets in \(Format.duration(b.end.timeIntervalSinceNow)).")
            }
        }

        // The previous 5-hour window ended.
        if let old = previous.activeBlock, current.activeBlock?.start != old.start, Date() >= old.end {
            notify("Fresh 5-hour window", "Your last session used \(Format.cost(old.totals.cost)).")
        }

        // Today's spend passed the daily alert amount.
        let daily = defaults.double(forKey: Prefs.dailyAlert)
        let today = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        if daily > 0, current.today.cost >= daily, defaults.double(forKey: "dailyAlertedDay") != today {
            defaults.set(today, forKey: "dailyAlertedDay")
            notify("Daily spend passed \(Format.cost(daily))", "Today so far: \(Format.cost(current.today.cost)).")
        }
    }

    private func notify(_ title: String, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

@main
struct UsageTrackerApp: App {
    @StateObject private var store = UsageStore()

    init() {
        // Debug flags: `--dump` prints the current numbers, `--render <file.png>` saves the panel.
        // Build flag: `--iconset <dir>` writes the app icon PNGs (see build.sh).
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--iconset"), i + 1 < args.count {
            do {
                try AppIcon.writeIconset(to: URL(fileURLWithPath: args[i + 1]))
                exit(0)
            } catch {
                print("Couldn't write iconset: \(error)")
                exit(1)
            }
        }
        if let i = args.firstIndex(of: "--render"), i + 1 < args.count {
            Self.renderPanel(to: args[i + 1])
            exit(0)
        }
        guard args.contains("--dump") else { return }
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            let s = await LogScanner().snapshot()
            print("today: \(Format.cost(s.today.cost)) \(Format.tokens(s.today.tokens)) tokens, \(s.today.requests) requests")
            print("7d:    \(Format.cost(s.week.cost)) \(Format.tokens(s.week.tokens)) tokens")
            print("30d:   \(Format.cost(s.month.cost)) \(Format.tokens(s.month.tokens)) tokens")
            if let b = s.activeBlock { print("session: \(Format.cost(b.totals.cost)), resets in \(Format.duration(b.end.timeIntervalSinceNow))") }
            print("peak past session: \(Format.cost(s.peakBlockCost)), limit hit: \(s.limitHitCost.map(Format.cost) ?? "never")")
            for m in s.models { print("  model \(m.name): \(Format.cost(m.totals.cost))") }
            for p in s.projects { print("  project \(p.name)\(p.isTemporary ? " (temp)" : ""): \(Format.cost(p.totals.cost))") }
            done.signal()
        }
        done.wait()
        exit(0)
    }

    @MainActor private static func renderPanel(to path: String) {
        let done = DispatchSemaphore(value: 0)
        var snapshot = UsageSnapshot()
        Task.detached { snapshot = await LogScanner().snapshot(); done.signal() }
        done.wait()
        let renderer = ImageRenderer(content: UsageView(store: UsageStore(preview: snapshot))
            .background(Color(nsColor: .windowBackgroundColor)))
        renderer.scale = 2
        if let tiff = renderer.nsImage?.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }

    var body: some Scene {
        MenuBarExtra {
            UsageView(store: store)
        } label: {
            MenuBarLabel(store: store, mascot: store.mascot)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Its own view so mascot frame ticks only re-render the label, not the panel.
private struct MenuBarLabel: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var mascot: MascotAnimator
    @AppStorage("labelMode") private var labelMode: LabelMode = .todayCost

    var body: some View {
        Image(nsImage: ClaudeIcon.image(frame: mascot.frame))
        if let text = labelText { Text(text) }
    }

    private var labelText: String? {
        let s = store.snapshot
        switch labelMode {
        case .todayCost: return Format.cost(s.today.cost)
        case .todayTokens: return Format.tokens(s.today.tokens)
        case .session:
            guard let b = s.activeBlock else { return "idle" }
            return "\(Format.cost(b.totals.cost)) · \(Format.duration(b.end.timeIntervalSinceNow))"
        case .iconOnly: return nil
        }
    }
}

enum Format {
    static func cost(_ v: Double) -> String {
        v >= 1000 ? String(format: "$%.0f", v) : String(format: "$%.2f", v)
    }

    static func tokens(_ v: Int) -> String {
        let d = Double(v)
        switch d {
        case 1e9...: return String(format: "%.1fB", d / 1e9)
        case 1e6...: return String(format: "%.1fM", d / 1e6)
        case 1e3...: return String(format: "%.1fK", d / 1e3)
        default: return "\(v)"
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let m = max(0, Int(seconds) / 60)
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }
}
