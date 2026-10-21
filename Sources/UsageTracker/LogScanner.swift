import Foundation

struct UsageEntry {
    let timestamp: Date
    let model: String
    let project: String
    let temporary: Bool
    let input: Int
    let output: Int
    let cacheWrite: Int
    let cacheRead: Int
    let cost: Double

    var tokens: Int { input + output + cacheWrite + cacheRead }
}

struct Totals {
    var cost = 0.0
    var input = 0
    var output = 0
    var cacheWrite = 0
    var cacheRead = 0
    var requests = 0

    var tokens: Int { input + output + cacheWrite + cacheRead }

    mutating func add(_ e: UsageEntry) {
        cost += e.cost
        input += e.input
        output += e.output
        cacheWrite += e.cacheWrite
        cacheRead += e.cacheRead
        requests += 1
    }
}

struct DayUsage: Identifiable {
    let date: Date
    var totals: Totals
    var id: Date { date }
}

struct NamedUsage: Identifiable {
    let name: String
    var totals: Totals
    var isTemporary = false
    var id: String { "\(isTemporary)\(name)" }
}

enum Projects {
    /// Folders Claude creates for throwaway work (scratch workspaces, side-session notes, temp dirs).
    private static let temporaryMarkers = [
        "/Library/Application Support/Claude/", "/private/tmp/", "/private/var/folders/", "/tmp/",
    ]

    static func classify(cwd: String?) -> (name: String, temporary: Bool) {
        guard let cwd else { return ("Unknown", false) }
        if temporaryMarkers.contains(where: cwd.contains) {
            return (URL(fileURLWithPath: cwd).lastPathComponent, true)
        }
        // Claude Code worktrees count toward the repo they came from.
        if let r = cwd.range(of: "/.claude/worktrees/") {
            return (URL(fileURLWithPath: String(cwd[..<r.lowerBound])).lastPathComponent, false)
        }
        return (URL(fileURLWithPath: cwd).lastPathComponent, false)
    }
}

/// A rolling 5-hour usage window, mirroring how Claude plan limits reset.
struct SessionBlock {
    static let length: TimeInterval = 5 * 3600
    let start: Date
    var lastActivity: Date
    var totals = Totals()
    var hitLimit = false
    var end: Date { start.addingTimeInterval(Self.length) }
}

struct SessionLimit {
    enum Source { case custom, calibrated, peak }
    let cost: Double
    let source: Source
}

struct UsageSnapshot {
    var today = Totals()
    var week = Totals()
    var month = Totals()
    var daily: [DayUsage] = []
    var models: [NamedUsage] = []
    var projects: [NamedUsage] = []
    /// Usage by [weekday][hour] over 30 days; weekday 0 is Monday.
    var heatmap = Array(repeating: Array(repeating: Totals(), count: 24), count: 7)
    var activeBlock: SessionBlock?
    var peakBlockCost = 0.0
    var peakBlockTokens = 0
    var limitHitCost: Double?
    var updated = Date()

    /// The 5-hour budget to measure against: your own setting, else the cost of a
    /// session where Claude reported hitting the limit, else your busiest past session.
    func limit(custom: Double) -> SessionLimit? {
        if custom > 0 { return SessionLimit(cost: custom, source: .custom) }
        if let hit = limitHitCost, hit > 0 { return SessionLimit(cost: hit, source: .calibrated) }
        if peakBlockCost > 0 { return SessionLimit(cost: peakBlockCost, source: .peak) }
        return nil
    }
}

/// Incrementally tails Claude Code's JSONL transcripts in ~/.claude/projects.
actor LogScanner {
    private var offsets: [String: UInt64] = [:]
    private var entries: [UsageEntry] = []
    private var indexByKey: [String: Int] = [:]
    private var limitHits: [Date] = []

    private let roots: [URL] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".claude/projects"),
            home.appendingPathComponent(".config/claude/projects"),
        ]
    }()

    private let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let iso = ISO8601DateFormatter()
    private let decoder = JSONDecoder()
    private let usageMarker = Data("\"usage\"".utf8)
    private let syntheticMarker = Data("<synthetic>".utf8)

    /// `knownReset` pins one session window to end at that time (e.g. the reset time shown on
    /// Claude's usage page); other windows are inferred from activity.
    func snapshot(now: Date = Date(), knownReset: Date? = nil) -> UsageSnapshot {
        scan()
        return aggregate(now: now, knownReset: knownReset)
    }

    // MARK: - Scanning

    private func scan() {
        let fm = FileManager.default
        for root in roots where fm.fileExists(atPath: root.path) {
            guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else { continue }
            for case let url as URL in walker where url.pathExtension == "jsonl" {
                read(url)
            }
        }
    }

    private func read(_ url: URL) {
        let size = UInt64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        var start = offsets[url.path] ?? 0
        if size < start { start = 0 }  // file was rewritten; dedupe keys protect us
        guard size > start, let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), let lastNewline = data.lastIndex(of: 0x0A) else { return }

        var lineStart = data.startIndex
        while lineStart <= lastNewline {
            let lineEnd = data[lineStart...lastNewline].firstIndex(of: 0x0A) ?? lastNewline
            let line = data[lineStart..<lineEnd]
            if line.firstRange(of: usageMarker) != nil || line.firstRange(of: syntheticMarker) != nil {
                ingest(line)
            }
            lineStart = lineEnd + 1
        }
        offsets[url.path] = start + UInt64(lastNewline - data.startIndex + 1)
    }

    private func ingest(_ line: Data) {
        guard let log = try? decoder.decode(LogLine.self, from: line),
              log.type == "assistant",
              let message = log.message, let model = message.model,
              let ts = log.timestamp,
              let date = isoFrac.date(from: ts) ?? iso.date(from: ts)
        else { return }

        // Claude Code writes a synthetic assistant message when you hit a usage limit.
        if model == "<synthetic>" {
            let text = message.content?.compactMap(\.text).joined(separator: " ").lowercased() ?? ""
            if text.contains("limit") { limitHits.append(date) }
            return
        }
        guard let usage = message.usage else { return }

        let input = usage.input_tokens ?? 0
        let output = usage.output_tokens ?? 0
        let cacheRead = usage.cache_read_input_tokens ?? 0
        let write1h = usage.cache_creation?.ephemeral_1h_input_tokens ?? 0
        let write5m = usage.cache_creation?.ephemeral_5m_input_tokens
            ?? max(0, (usage.cache_creation_input_tokens ?? 0) - write1h)

        var cost = 0.0
        if let p = Pricing.price(for: model) {
            cost = (Double(input) * p.input
                + Double(output) * p.output
                + Double(cacheRead) * p.cacheRead
                + Double(write5m) * p.cacheWrite5m
                + Double(write1h) * p.cacheWrite1h) / 1_000_000
            if usage.speed == "fast" { cost *= 2 }
        }

        let project = Projects.classify(cwd: log.cwd)
        let entry = UsageEntry(timestamp: date, model: model, project: project.name, temporary: project.temporary,
                               input: input, output: output,
                               cacheWrite: write5m + write1h, cacheRead: cacheRead, cost: cost)

        // A single response is logged once per content block; keep the most complete copy.
        if let id = message.id {
            let key = "\(id):\(log.requestId ?? "")"
            if let i = indexByKey[key] {
                if entry.output > entries[i].output { entries[i] = entry }
                return
            }
            indexByKey[key] = entries.count
        }
        entries.append(entry)
    }

    // MARK: - Aggregation

    private func aggregate(now: Date, knownReset: Date?) -> UsageSnapshot {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let weekStart = cal.date(byAdding: .day, value: -6, to: today)!
        let monthStart = cal.date(byAdding: .day, value: -29, to: today)!
        let chartStart = cal.date(byAdding: .day, value: -13, to: today)!

        var snap = UsageSnapshot(updated: now)
        var days: [Date: Totals] = [:]
        var models: [String: Totals] = [:]
        var projects: [ProjectKey: Totals] = [:]
        var blocks: [SessionBlock] = []
        let pinnedStart = knownReset?.addingTimeInterval(-SessionBlock.length)

        for e in entries.sorted(by: { $0.timestamp < $1.timestamp }) {
            let t = e.timestamp
            if t >= today { snap.today.add(e) }
            if t >= weekStart { snap.week.add(e) }
            if t >= monthStart {
                snap.month.add(e)
                models[Pricing.displayName(for: e.model), default: Totals()].add(e)
                projects[ProjectKey(name: e.project, temporary: e.temporary), default: Totals()].add(e)
                let c = cal.dateComponents([.weekday, .hour], from: t)
                snap.heatmap[(c.weekday! + 5) % 7][c.hour!].add(e)
            }
            if t >= chartStart { days[cal.startOfDay(for: t), default: Totals()].add(e) }

            if let pinned = pinnedStart, t >= pinned, t < pinned.addingTimeInterval(SessionBlock.length),
               blocks.last?.start != pinned {
                // Entering the known window: it starts exactly here, cutting short any guessed one.
                blocks.append(SessionBlock(start: pinned, lastActivity: t))
            } else if let last = blocks.last, t < last.end {
                blocks[blocks.count - 1].lastActivity = t
            } else {
                // A new window opens on the hour of the first request, but never overlaps the previous one.
                let hour = cal.dateInterval(of: .hour, for: t)!.start
                blocks.append(SessionBlock(start: max(hour, blocks.last?.end ?? hour), lastActivity: t))
            }
            blocks[blocks.count - 1].totals.add(e)
        }

        for hit in limitHits {
            if let i = blocks.lastIndex(where: { $0.start <= hit && hit < $0.end }) { blocks[i].hitLimit = true }
        }
        var completed = blocks[...]
        if let b = blocks.last, now < b.end {
            snap.activeBlock = b
            completed = completed.dropLast()
        }
        if let peak = completed.max(by: { $0.totals.cost < $1.totals.cost }) {
            snap.peakBlockCost = peak.totals.cost
            snap.peakBlockTokens = peak.totals.tokens
        }
        snap.limitHitCost = blocks.filter(\.hitLimit).map(\.totals.cost).max()

        snap.daily = (0..<14).map { i in
            let d = cal.date(byAdding: .day, value: i, to: chartStart)!
            return DayUsage(date: d, totals: days[d] ?? Totals())
        }
        snap.models = models.map { NamedUsage(name: $0.key, totals: $0.value) }.sorted { $0.totals.cost > $1.totals.cost }
        snap.projects = projects.map { NamedUsage(name: $0.key.name, totals: $0.value, isTemporary: $0.key.temporary) }.sorted { $0.totals.cost > $1.totals.cost }
        return snap
    }
}

private struct ProjectKey: Hashable {
    let name: String
    let temporary: Bool
}

private struct LogLine: Decodable {
    let type: String?
    let timestamp: String?
    let requestId: String?
    let cwd: String?
    let message: Message?

    struct Message: Decodable {
        let id: String?
        let model: String?
        let usage: Usage?
        let content: [Content]?

        enum CodingKeys: String, CodingKey { case id, model, usage, content }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try? c.decode(String.self, forKey: .id)
            model = try? c.decode(String.self, forKey: .model)
            usage = try? c.decode(Usage.self, forKey: .usage)
            content = try? c.decode([Content].self, forKey: .content)
        }
    }

    struct Content: Decodable {
        let text: String?
    }

    struct Usage: Decodable {
        let input_tokens: Int?
        let output_tokens: Int?
        let cache_creation_input_tokens: Int?
        let cache_read_input_tokens: Int?
        let cache_creation: CacheCreation?
        let speed: String?
    }

    struct CacheCreation: Decodable {
        let ephemeral_5m_input_tokens: Int?
        let ephemeral_1h_input_tokens: Int?
    }
}
