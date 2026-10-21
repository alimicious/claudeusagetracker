import AppKit

/// Drives the menu bar mascot: it types on a mini laptop while Claude Code is working and blinks
/// now and then when idle. Kept separate from UsageStore so frame ticks don't re-render the panel.
@MainActor
final class MascotAnimator: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case whileWorking = "While Claude works"
        case always = "Always"
        case off = "Off"
        var id: String { rawValue }
    }

    static let modeKey = "mascotAnimation"

    /// Bursts of alternating key presses with a short pause, so the typing doesn't look mechanical.
    private static let typingLoop: [ClaudeIcon.Frame] = [
        .typeLeft, .typeRight, .typeLeft, .typeRight, .typeLeft, .typeRight, .typeRest, .typeRest,
    ]

    @Published private(set) var frame: ClaudeIcon.Frame = .idle
    private var working = false
    private var typeTimer: Timer?
    private var step = 0

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

    /// Re-evaluates whether to type; call after the mode setting changes.
    func update() {
        let shouldType = motionAllowed && (mode == .always || working)
        if shouldType, typeTimer == nil {
            step = 0
            frame = .typeRest
            let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
            RunLoop.main.add(timer, forMode: .common)  // keep ticking while the panel is open
            typeTimer = timer
        } else if !shouldType, let timer = typeTimer {
            timer.invalidate()
            typeTimer = nil
            frame = .idle
        }
    }

    private func tick() {
        guard typeTimer != nil else { return }  // a tick queued just before the timer was stopped
        frame = Self.typingLoop[step % Self.typingLoop.count]
        step += 1
    }

    private func blinkLoop() async {
        while true {
            try? await Task.sleep(for: .seconds(Double.random(in: 4...8)))
            guard typeTimer == nil, motionAllowed else { continue }
            frame = .blink
            try? await Task.sleep(for: .milliseconds(150))
            if typeTimer == nil { frame = .idle }
        }
    }
}
