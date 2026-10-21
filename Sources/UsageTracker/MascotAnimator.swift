import AppKit

/// Drives the menu bar mascot: it walks while Claude Code is working and blinks now and then
/// when idle. Kept separate from UsageStore so frame ticks don't re-render the whole panel.
@MainActor
final class MascotAnimator: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case whileWorking = "While Claude works"
        case always = "Always"
        case off = "Off"
        var id: String { rawValue }
    }

    static let modeKey = "mascotAnimation"

    @Published private(set) var frame: ClaudeIcon.Frame = .idle
    private var working = false
    private var walkTimer: Timer?

    init() {
        Task { await blinkLoop() }
    }

    private var mode: Mode {
        Mode(rawValue: UserDefaults.standard.string(forKey: Self.modeKey) ?? "") ?? .whileWorking
    }

    private var motionAllowed: Bool {
        mode != .off && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func setWorking(_ isWorking: Bool) {
        working = isWorking
        update()
    }

    /// Re-evaluates whether to walk; call after the mode setting changes.
    func update() {
        let shouldWalk = motionAllowed && (mode == .always || working)
        if shouldWalk, walkTimer == nil {
            let timer = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.step() }
            }
            RunLoop.main.add(timer, forMode: .common)  // keep ticking while the panel is open
            walkTimer = timer
        } else if !shouldWalk, let timer = walkTimer {
            timer.invalidate()
            walkTimer = nil
            frame = .idle
        }
    }

    private func step() {
        guard walkTimer != nil else { return }  // a tick queued just before the timer was stopped
        frame = frame == .walkA ? .walkB : .walkA
    }

    private func blinkLoop() async {
        while true {
            try? await Task.sleep(for: .seconds(Double.random(in: 4...8)))
            guard walkTimer == nil, motionAllowed else { continue }
            frame = .blink
            try? await Task.sleep(for: .milliseconds(150))
            if walkTimer == nil { frame = .idle }
        }
    }
}
