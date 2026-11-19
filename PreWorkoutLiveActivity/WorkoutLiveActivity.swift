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
/// rest countdown and the current exercise. Clocks tick on their own
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
                    if state.hasRest {
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
                Image(systemName: state.hasRest ? "timer" : "figure.strengthtraining.traditional")
                    .foregroundStyle(state.hasRest ? .orange : .green)
            } compactTrailing: {
                Group {
                    if state.hasRest { RestClock(state: state) } else { WorkoutClock(state: state) }
                }
                .monospacedDigit()
                .frame(maxWidth: 56)
                .foregroundStyle(state.hasRest ? .orange : .green)
            } minimal: {
                Image(systemName: state.hasRest ? "timer" : "figure.strengthtraining.traditional")
                    .foregroundStyle(state.hasRest ? .orange : .green)
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
            if state.hasRest {
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
        if let paused = state.pausedElapsed {
            Text(verbatim: format(paused))
        } else {
            Text(timerInterval: state.clockStart...Date.distantFuture, countsDown: false)
        }
    }
}

/// Rest countdown (frozen while paused, 0:00 when over).
private struct RestClock: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        if let paused = state.restPausedRemaining {
            Text(verbatim: format(paused))
        } else if let end = state.restEnd, end > Date() {
            Text(timerInterval: Date()...end, countsDown: true)
        } else {
            Text(verbatim: "0:00")
        }
    }
}

private func format(_ seconds: Int) -> String {
    let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}

extension WorkoutActivityAttributes.ContentState {
    var hasRest: Bool { restEnd != nil || restPausedRemaining != nil }
}
