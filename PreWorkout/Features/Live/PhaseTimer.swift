import Foundation

/// Wall-clock timer for a live set today, and for an interval phase later.
/// Every instant is an absolute epoch (milliseconds), never a running
/// in-memory counter, so backgrounding or killing the app does not skew
/// time. A countdown never auto-stops: after the target it continues as
/// overtime until the caller records the set.
struct PhaseTimer: Codable, Hashable, Sendable {
    /// Epoch milliseconds.
    var startedAt: Double
    /// Elapsed seconds while the parent session is paused; nil = running.
    var pausedElapsed: Double?
    /// Optional target in seconds. For a countdown this is the duration
    /// to zero; for a stopwatch it is only a "goal reached" cue (holds).
    var targetSec: Double?
    /// True after the target was reached (the signal already fired).
    var alerted: Bool
    /// When true, the UI and Live Activity count down to zero, then
    /// overtime. When false, the timer always counts up (an optional
    /// target is only a goal).
    var countsDown: Bool

    private enum CodingKeys: String, CodingKey {
        case startedAt, pausedElapsed, targetSec, alerted, countsDown
    }

    init(startedAt: Double, targetSec: Double?, countsDown: Bool = false) {
        self.startedAt = startedAt
        let clamped = targetSec.map { Limits.durationSeconds.clamp($0) }.flatMap { $0 >= 1 ? $0 : nil }
        self.targetSec = clamped
        self.pausedElapsed = nil
        self.alerted = false
        self.countsDown = countsDown && clamped != nil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startedAt = try c.decode(Double.self, forKey: .startedAt)
        pausedElapsed = try c.decodeIfPresent(Double.self, forKey: .pausedElapsed)
        targetSec = try c.decodeIfPresent(Double.self, forKey: .targetSec)
        alerted = try c.decodeIfPresent(Bool.self, forKey: .alerted) ?? false
        countsDown = try c.decodeIfPresent(Bool.self, forKey: .countsDown) ?? false
    }

    func elapsed(_ now: Double) -> Double {
        pausedElapsed ?? max(0, (now - startedAt) / 1000)
    }

    /// Seconds left until the target; negative means overtime. nil if no target.
    func remaining(_ now: Double) -> Double? {
        guard let target = targetSec else { return nil }
        return target - elapsed(now)
    }

    func isOvertime(_ now: Double) -> Bool {
        countsDown && (remaining(now) ?? 1) <= 0
    }

    /// Absolute instant when a running countdown hits zero. nil while paused
    /// (the end date is recomputed on resume, after `startedAt` is shifted).
    func endDate() -> Date? {
        guard countsDown, let target = targetSec, pausedElapsed == nil else { return nil }
        return Date(timeIntervalSince1970: startedAt / 1000 + target)
    }

    /// True when the target has just been reached and a signal is due.
    func shouldAlert(_ now: Double) -> Bool {
        guard !alerted, let target = targetSec else { return false }
        return elapsed(now) >= target
    }

    /// Whole seconds to show on the clock: elapsed for a stopwatch, remaining
    /// for a countdown (negative = overtime). `Clock.text` already prints the "+".
    func displaySeconds(_ now: Double) -> Double {
        if countsDown, let left = remaining(now) {
            return left >= 0 ? left.rounded(.down) : -((-left).rounded(.down))
        }
        return elapsed(now).rounded(.down)
    }

    /// Seconds written into the set: actual elapsed, at least 1, inside the
    /// duration limit.
    func recordedSeconds(_ now: Double) -> Int {
        Limits.durationSeconds.clamp(max(1, elapsed(now))).safeInt
    }
}

/// The session JSON still calls this `setTimer`; the shape is `PhaseTimer`.
typealias LiveSetTimer = PhaseTimer

/// How a timed set is measured in the live workout. Remembered per exercise.
enum TimedSetMode: String, CaseIterable, Identifiable, Sendable {
    case stopwatch, countdown, manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stopwatch: return String(localized: "Stoper")
        case .countdown: return String(localized: "Odliczanie")
        case .manual: return String(localized: "Ręcznie")
        }
    }
}
