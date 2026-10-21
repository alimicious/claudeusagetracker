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

/// UserDefaults keys shared between the store and @AppStorage in the views.
enum Prefs {
    static let sessionLimit = "sessionLimit"      // Double, 0 = auto
    static let notifications = "notifications"    // Bool
    static let dailyAlert = "dailyAlert"          // Double, 0 = off
}

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot = UsageSnapshot()
    @Published private(set) var isLoading = false
    @Published var showSettings = false
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    private let scanner = LogScanner()
    private var hasLoaded = false

    /// A static store for rendering the panel without a menu bar (see `--render`).
    init(preview: UsageSnapshot) {
        snapshot = preview
    }

    init() {
        Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        let previous = snapshot
        snapshot = await scanner.snapshot()
        if hasLoaded { sendAlerts(previous: previous, current: snapshot) }
        hasLoaded = true
        isLoading = false
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
    @AppStorage("labelMode") private var labelMode: LabelMode = .todayCost

    init() {
        // Debug flags: `--dump` prints the current numbers, `--render <file.png>` saves the panel.
        let args = CommandLine.arguments
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
            Image(nsImage: ClaudeIcon.image())
            if let text = labelText { Text(text) }
        }
        .menuBarExtraStyle(.window)
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
