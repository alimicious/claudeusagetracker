import Charts
import SwiftUI

struct UsageView: View {
    @ObservedObject var store: UsageStore
    @AppStorage("labelMode") private var labelMode: LabelMode = .todayCost
    @AppStorage("breakdown") private var breakdown = "Projects"
    @AppStorage("hideTemporary") private var hideTemporary = true
    @AppStorage("displayUnit") private var unit: DisplayUnit = .cost
    @AppStorage(MascotAnimator.modeKey) private var mascotMode: MascotAnimator.Mode = .whileWorking
    @AppStorage(Prefs.sessionLimit) private var customLimit = 0.0
    @AppStorage(Prefs.notifications) private var notifications = false
    @AppStorage(Prefs.dailyAlert) private var dailyAlert = 0.0

    private var s: UsageSnapshot { store.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            sessionHero
            periodRow
            dailyChart
            breakdownList
            heatmap
            footer
        }
        .padding(18)
        .frame(width: 360)
        .task { await store.refresh() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: ClaudeIcon.image(size: 24))
            VStack(alignment: .leading, spacing: 1) {
                Text("Claude Code").font(.headline)
                Text("Updated \(s.updated.formatted(date: .omitted, time: .shortened)) · est. at API rates")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            // Swap in a spinner rather than animating the icon: a repeating animation
            // inside a MenuBarExtra window can leave the button stuck mid-transition.
            if store.isLoading {
                ProgressView().controlSize(.small).frame(width: 22, height: 22)
            } else {
                IconButton(systemName: "arrow.clockwise", help: "Refresh") { Task { await store.refresh() } }
            }
            // Settings open in a popover so the panel never changes height; MenuBarExtra
            // windows don't resize cleanly when their content grows or shrinks.
            IconButton(systemName: store.showSettings ? "gearshape.fill" : "gearshape", help: "Settings") {
                store.showSettings.toggle()
            }
            .popover(isPresented: $store.showSettings, arrowEdge: .bottom) { settings }
        }
    }

    // MARK: - Session

    private var sessionHero: some View {
        let limit = s.limit(custom: customLimit)
        let block = s.activeBlock
        let used = block.flatMap { b in limit.map { b.totals.cost / $0.cost } } ?? 0
        let elapsed = block.map { min(1, Date().timeIntervalSince($0.start) / SessionBlock.length) } ?? 0

        return HStack(spacing: 18) {
            SessionRing(used: used, elapsed: elapsed, active: block != nil)
            VStack(alignment: .leading, spacing: 4) {
                Text("5-hour session").font(.caption).foregroundStyle(.secondary)
                if let b = block {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(unit.format(b.totals)).font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                        if unit == .tokens { Text("tokens").font(.caption).foregroundStyle(.secondary) }
                    }
                    // Captions stay on one line so the card's height never changes.
                    if let limit {
                        Text(limitCaption(limit)).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.75)
                    }
                    Label("Resets in \(Format.duration(b.end.timeIntervalSinceNow))", systemImage: "clock")
                        .font(.caption.weight(.medium))
                    let hours = Date().timeIntervalSince(b.start) / 3600
                    if hours > 0.15 {
                        let perHour = unit.value(b.totals) / hours
                        Text("\(unit.format(perHour))/hr · on pace for \(unit.format(perHour * 5))")
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75)
                    }
                } else {
                    Text("Idle").font(.system(size: 26, weight: .semibold, design: .rounded))
                    Text("A new window starts with your next request").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16.8).fill(.quinary))
    }

    private func limitCaption(_ limit: SessionLimit) -> String {
        switch limit.source {
        case .custom: return "of your \(Format.cost(limit.cost)) limit"
        case .calibrated: return "of ~\(Format.cost(limit.cost)) limit (calibrated)"
        case .peak:
            return unit == .tokens
                ? "vs. busiest session, \(Format.tokens(s.peakBlockTokens))"
                : "vs. your busiest session, \(Format.cost(limit.cost))"
        }
    }

    // MARK: - Periods & chart

    private var periodRow: some View {
        HStack(spacing: 0) {
            PeriodStat(title: "Today", totals: s.today, unit: unit)
            Divider().frame(height: 30)
            PeriodStat(title: "7 days", totals: s.week, unit: unit)
            Divider().frame(height: 30)
            PeriodStat(title: "30 days", totals: s.month, unit: unit)
        }
    }

    private var dailyChart: some View {
        Titled(title: "Last 14 days") {
            Chart(s.daily) { day in
                BarMark(x: .value("Day", day.date, unit: .day), y: .value(unit.rawValue, unit.value(day.totals)))
                    .foregroundStyle(Calendar.current.isDateInToday(day.date) ? Color(nsColor: ClaudeIcon.terracotta) : Color.secondary.opacity(0.35))
                    .cornerRadius(3.6)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 3)) {
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text(unit == .cost ? "$\(Int(v))" : Format.tokens(Int(v))) }
                    }
                }
            }
            .frame(height: 84)
        }
    }

    // MARK: - Breakdown

    private var breakdownList: some View {
        let showingProjects = breakdown == "Projects"
        let items = showingProjects && hideTemporary ? s.projects.filter { !$0.isTemporary } : (showingProjects ? s.projects : s.models)
        let hidden = s.projects.filter(\.isTemporary).reduce(0) { $0 + unit.value($1.totals) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Last 30 days").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $breakdown) {
                    Text("Projects").tag("Projects")
                    Text("Models").tag("Models")
                }
                .pickerStyle(.segmented).labelsHidden().controlSize(.small).fixedSize()
            }
            // Always lay out 5 rows and the footnote, so switching tabs never changes the
            // panel's height (MenuBarExtra windows don't resize cleanly).
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<5, id: \.self) { i in
                    if i < items.count {
                        breakdownRow(items[i])
                    } else {
                        breakdownRow(NamedUsage(name: " ", totals: Totals())).hidden()
                    }
                }
            }
            .overlay {
                if items.isEmpty { Text("No usage yet").font(.caption).foregroundStyle(.secondary) }
            }
            Text("+ \(unit.format(hidden))\(unit == .tokens ? " tokens" : "") in temporary folders (hidden)")
                .font(.caption2).foregroundStyle(.tertiary)
                .opacity(showingProjects && hideTemporary && hidden > 0 ? 1 : 0)
        }
    }

    private func breakdownRow(_ item: NamedUsage) -> some View {
        let total = unit.value(s.month)
        let share = total > 0 ? unit.value(item.totals) / total : 0
        return VStack(spacing: 4) {
            HStack {
                Text(item.name).font(.caption).lineLimit(1).truncationMode(.middle)
                if item.isTemporary {
                    Text("temp").font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(.quinary))
                }
                Spacer()
                Text(unit.format(item.totals)).font(.caption).monospacedDigit()
                Text("\(Int((share * 100).rounded()))%").font(.caption2).monospacedDigit()
                    .foregroundStyle(.secondary).frame(width: 30, alignment: .trailing)
            }
            GeometryReader { geo in
                Capsule().fill(.quinary)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color(nsColor: ClaudeIcon.terracotta).opacity(0.8))
                            .frame(width: max(3, geo.size.width * share))
                    }
            }
            .frame(height: 4)
        }
    }

    // MARK: - Heatmap

    private var heatmap: some View {
        let peak = s.heatmap.flatMap { $0 }.map(unit.value).max() ?? 0
        let days = ["M", "T", "W", "T", "F", "S", "S"]
        return Titled(title: "Active hours · 30 days") {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(0..<7, id: \.self) { d in
                    HStack(spacing: 2) {
                        Text(days[d]).font(.system(size: 8)).foregroundStyle(.secondary).frame(width: 10)
                        ForEach(0..<24, id: \.self) { h in
                            let v = peak > 0 ? unit.value(s.heatmap[d][h]) / peak : 0
                            RoundedRectangle(cornerRadius: 2.4)
                                .fill(v > 0 ? Color(nsColor: ClaudeIcon.terracotta).opacity(0.2 + 0.8 * v) : Color.secondary.opacity(0.1))
                                .frame(width: 11, height: 11)
                                .help("\(days[d]) \(h):00 · \(unit.format(s.heatmap[d][h]))")
                        }
                    }
                }
                HStack(spacing: 0) {
                    Spacer().frame(width: 12)
                    ForEach(["12a", "6a", "12p", "6p"], id: \.self) { label in
                        Text(label).font(.system(size: 8)).foregroundStyle(.secondary).frame(width: 78, alignment: .leading)
                    }
                }
            }
        }
    }

    // MARK: - Settings & footer

    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingRow("Menu bar shows") {
                Picker("", selection: $labelMode) {
                    ForEach(LabelMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden().fixedSize()
            }
            SettingRow("Animate mascot") {
                Picker("", selection: $mascotMode) {
                    ForEach(MascotAnimator.Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden().fixedSize()
                .onChange(of: mascotMode) { store.mascot.update() }
            }
            SettingRow("Show amounts as") {
                Picker("", selection: $unit) {
                    ForEach(DisplayUnit.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().controlSize(.small).fixedSize()
            }
            SettingRow("Hide temporary folders") {
                Toggle("", isOn: $hideTemporary).toggleStyle(.switch).controlSize(.mini).labelsHidden()
            }
            SettingRow("Session limit", hint: "0 = auto") {
                TextField("Auto", value: $customLimit, format: .currency(code: "USD"))
                    .frame(width: 80).multilineTextAlignment(.trailing)
            }
            SettingRow("Notifications") {
                Toggle("", isOn: Binding(get: { notifications }, set: { store.setNotifications($0) }))
                    .toggleStyle(.switch).controlSize(.mini).labelsHidden()
            }
            if notifications {
                SettingRow("Alert when today passes", hint: "0 = off") {
                    TextField("Off", value: $dailyAlert, format: .currency(code: "USD"))
                        .frame(width: 80).multilineTextAlignment(.trailing)
                }
            }
            SettingRow("Launch at login") {
                Toggle("", isOn: Binding(get: { store.launchAtLogin }, set: { store.setLaunchAtLogin($0) }))
                    .toggleStyle(.switch).controlSize(.mini).labelsHidden()
            }
        }
        .font(.caption)
        .padding(14)
        .frame(width: 290)
    }

    private var footer: some View {
        HStack {
            Text("Reads ~/.claude/projects").font(.caption2).foregroundStyle(.tertiary)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q").buttonStyle(.borderless).font(.caption)
        }
    }
}

// MARK: - Components

private struct SessionRing: View {
    let used: Double
    let elapsed: Double
    let active: Bool

    private var color: Color {
        used < 0.6 ? .green : used < 0.85 ? .orange : .red
    }

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 9)
            Circle().trim(from: 0, to: min(used, 1))
                .stroke(color.gradient, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            // Inner ring: how far through the 5-hour window you are.
            Circle().trim(from: 0, to: elapsed)
                .stroke(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(10)
            VStack(spacing: 0) {
                Text(active ? "\(Int((used * 100).rounded()))%" : "–")
                    .font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
                Text("used").font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 92, height: 92)
        .animation(.easeOut(duration: 0.6), value: used)
        .help("Outer ring: usage vs. limit · inner ring: time elapsed in the window")
    }
}

private struct PeriodStat: View {
    let title: String
    let totals: Totals
    let unit: DisplayUnit

    var body: some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(unit.format(totals)).font(.system(.callout, design: .rounded).weight(.semibold)).monospacedDigit()
            Text(unit.secondary(totals)).font(.system(size: 9)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .help("In \(Format.tokens(totals.input)) · Out \(Format.tokens(totals.output)) · Cache write \(Format.tokens(totals.cacheWrite)) · Cache read \(Format.tokens(totals.cacheRead)) · \(totals.requests) requests")
    }
}

private struct Titled<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            content
        }
    }
}

private struct SettingRow<Control: View>: View {
    let title: String
    let hint: String?
    @ViewBuilder let control: Control

    init(_ title: String, hint: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.hint = hint
        self.control = control()
    }

    var body: some View {
        HStack {
            Text(title)
            if let hint { Text(hint).foregroundStyle(.tertiary) }
            Spacer()
            control
        }
    }
}

private struct IconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName).font(.system(size: 12, weight: .medium)).frame(width: 22, height: 22)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}
