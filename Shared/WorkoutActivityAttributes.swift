import ActivityKit
import Foundation

/// Live Activity of a running workout (Lock Screen + Dynamic Island).
/// Shared by the app and the PreWorkoutLiveActivity widget extension.
struct WorkoutActivityAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        /// Workout start shifted by the paused time: `Text(timerInterval:)` counts from here.
        var clockStart: Date
        /// Elapsed seconds while paused (the clock is frozen); nil = running.
        var pausedElapsed: Int?
        /// End of the running rest; nil = no rest.
        var restEnd: Date?
        /// Rest seconds left while paused.
        var restPausedRemaining: Int?
        /// Current exercise name.
        var exercise: String
        /// "Seria 2 z 4" style progress line (already localized by the app).
        var detail: String
        /// Stopwatch start for a running count-up set timer.
        var setStopwatchStart: Date?
        /// End of a running set countdown (`Text(timerInterval:countsDown:)`).
        var setCountdownEnd: Date?
        /// When the countdown has hit zero, count up from this instant as overtime.
        var setOvertimeStart: Date?
        /// Frozen set-timer seconds while paused (negative = overtime).
        var setPausedSeconds: Int?
    }

    /// Workout title or a localized "Workout".
    var title: String
}

extension WorkoutActivityAttributes.ContentState {
    var hasRest: Bool { restEnd != nil || restPausedRemaining != nil }
    var hasSetTimer: Bool {
        setStopwatchStart != nil || setCountdownEnd != nil || setOvertimeStart != nil || setPausedSeconds != nil
    }
}
