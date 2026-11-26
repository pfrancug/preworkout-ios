import ActivityKit
import SwiftUI
import WidgetKit

@main
struct PreWorkoutLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivity()
    }
}

/// Lock Screen banner and Dynamic Island of a running workout: workout clock,
/// rest or set countdown, and the current exercise. Clocks tick on their own
/// (`Text(timerInterval:)`), so the app only updates on real changes.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenView(title: context.attributes.title, state: context.state)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.green)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        WorkoutClock(state: state).font(.title3.monospacedDigit().weight(.semibold))
                    } icon: {
                        Image(systemName: state.pausedElapsed == nil ? "figure.strengthtraining.traditional" : "pause.fill")
                            .foregroundStyle(.green)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if state.hasSetTimer {
                        Label {
                            SetClock(state: state).font(.title3.monospacedDigit().weight(.semibold))
                        } icon: {
                            Image(systemName: state.setTimerSymbol).foregroundStyle(state.setTimerColor)
                        }
                        .padding(.trailing, 4)
                    } else if state.hasRest {
                        Label {
                            RestClock(state: state).font(.title3.monospacedDigit().weight(.semibold))
                        } icon: {
                            Image(systemName: "timer").foregroundStyle(.orange)
                        }
                        .padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 2) {
                        Text(verbatim: state.exercise).font(.headline).lineLimit(1)
                        if !state.detail.isEmpty {
                            Text(verbatim: state.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: state.hasSetTimer ? state.setTimerSymbol : (state.hasRest ? "timer" : "figure.strengthtraining.traditional"))
                    .foregroundStyle(state.hasSetTimer ? state.setTimerColor : (state.hasRest ? .orange : .green))
            } compactTrailing: {
                Group {
                    if state.hasSetTimer {
                        SetClock(state: state)
                    } else if state.hasRest {
                        RestClock(state: state)
                    } else {
                        WorkoutClock(state: state)
                    }
                }
                .monospacedDigit()
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: 72)
                .foregroundStyle(state.hasSetTimer ? state.setTimerColor : (state.hasRest ? .orange : .green))
            } minimal: {
                Image(systemName: state.hasSetTimer ? state.setTimerSymbol : (state.hasRest ? "timer" : "figure.strengthtraining.traditional"))
                    .foregroundStyle(state.hasSetTimer ? state.setTimerColor : (state.hasRest ? .orange : .green))
            }
        }
    }
}

private struct LockScreenView: View {
    let title: String
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: state.pausedElapsed == nil ? "figure.strengthtraining.traditional" : "pause.fill")
                    Text(verbatim: title).lineLimit(1)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
                WorkoutClock(state: state)
                    .font(.title.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white)
                Text(verbatim: state.exercise)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !state.detail.isEmpty {
                    Text(verbatim: state.detail).font(.caption).foregroundStyle(.white.opacity(0.7))
                }
            }
            Spacer()
            if state.hasSetTimer {
                VStack(spacing: 4) {
                    Image(systemName: state.setTimerSymbol).font(.title3)
                    SetClock(state: state)
                        .font(.title.monospacedDigit().weight(.bold))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(state.setTimerColor)
                .frame(minWidth: 90)
            } else if state.hasRest {
                VStack(spacing: 4) {
                    Image(systemName: "timer").font(.title3)
                    RestClock(state: state)
                        .font(.title.monospacedDigit().weight(.bold))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.orange)
                .frame(minWidth: 90)
            }
        }
    }
}

/// Elapsed workout time (frozen while paused).
private struct WorkoutClock: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        Group {
            if let paused = state.pausedElapsed {
                Text(verbatim: format(paused))
            } else {
                Text(timerInterval: state.clockStart...Date.distantFuture, countsDown: false)
            }
        }
        // Past 1:00:00 the text must shrink, never wrap to a second line.
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// Rest countdown (frozen while paused, 0:00 when over).
private struct RestClock: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        Group {
            if let paused = state.restPausedRemaining {
                Text(verbatim: format(paused))
            } else if let end = state.restEnd, end > Date() {
                Text(timerInterval: Date()...end, countsDown: true)
            } else {
                Text(verbatim: "0:00")
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// Set stopwatch, countdown, or overtime. After zero a countdown does not
/// freeze at 0:00 — it counts up from the end date with a "+" prefix.
private struct SetClock: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        Group {
            if let paused = state.setPausedSeconds {
                Text(verbatim: formatSigned(paused))
            } else if let end = state.setCountdownEnd, end > Date() {
                Text(timerInterval: Date()...end, countsDown: true)
            } else if let start = state.setOvertimeStart {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(verbatim: "+")
                    Text(timerInterval: start...Date.distantFuture, countsDown: false)
                }
            } else if let start = state.setStopwatchStart {
                Text(timerInterval: start...Date.distantFuture, countsDown: false)
            } else if let end = state.setCountdownEnd {
                // Crossed zero before the app could flip to overtime.
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(verbatim: "+")
                    Text(timerInterval: end...Date.distantFuture, countsDown: false)
                }
            } else {
                Text(verbatim: "0:00")
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

private func format(_ seconds: Int) -> String {
    let total = abs(seconds)
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}

private func formatSigned(_ seconds: Int) -> String {
    let body = format(seconds)
    return seconds < 0 ? "+" + body : body
}

extension WorkoutActivityAttributes.ContentState {
    var setTimerColor: Color {
        if setOvertimeStart != nil || (setPausedSeconds ?? 0) < 0 { return .pink }
        if setCountdownEnd != nil { return .orange }
        return .green
    }

    var setTimerSymbol: String {
        if setOvertimeStart != nil || (setPausedSeconds ?? 0) < 0 { return "plus.circle.fill" }
        if setCountdownEnd != nil { return "timer" }
        return "stopwatch"
    }
}
