import SwiftUI

/// Segmented stopwatch / countdown / manual picker for a timed set.
struct TimerModePicker: View {
    @Binding var mode: TimedSetMode
    var enabled = true

    var body: some View {
        Picker("Tryb timera", selection: $mode) {
            ForEach(TimedSetMode.allCases) { item in
                Text(verbatim: item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
        .accessibilityLabel(Text("Tryb timera"))
    }
}

/// Target for a countdown: quick presets, a stepper, and an optional wheel.
struct CountdownTargetEditor: View {
    @Binding var seconds: Double
    var presets: [Int] = [10, 15, 20, 25, 30, 45, 60, 90, 120, 180, 300]
    @State private var showWheel = false

    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(presets, id: \.self) { preset in
                        let on = seconds.safeInt == preset
                        Button {
                            seconds = Double(preset)
                        } label: {
                            Text(verbatim: Clock.text(Double(preset)))
                                .font(.system(size: 13, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(on ? LV.text : LV.muted)
                                .padding(.horizontal, 10)
                                .frame(height: 32)
                                .background(on ? LV.gold.opacity(0.28) : Color.white.opacity(0.08), in: Capsule())
                                .overlay(Capsule().stroke(on ? LV.gold.opacity(0.75) : Color.clear, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: Clock.text(Double(preset))))
                    }
                }
            }
            HStack(spacing: 14) {
                LVStepButton(up: false, size: 44, disabled: seconds <= 1) {
                    bump(-step)
                }
                Button {
                    withAnimation(.snappy) { showWheel.toggle() }
                } label: {
                    Text(verbatim: Clock.text(seconds))
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(showWheel ? LV.gold : LV.text)
                        .frame(minWidth: 88)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Czas odliczania"))
                LVStepButton(up: true, size: 44, disabled: seconds >= Limits.durationSeconds.max) {
                    bump(step)
                }
            }
            if showWheel {
                DurationWheel(
                    seconds: Binding(
                        get: { seconds },
                        set: { seconds = clamp($0) }
                    ),
                    maxHours: 24
                )
            }
        }
    }

    private var step: Double { seconds <= 30 ? 1 : 5 }

    private func bump(_ delta: Double) {
        seconds = clamp(seconds + delta)
    }

    private func clamp(_ value: Double) -> Double {
        Limits.durationSeconds.clamp(max(1, value))
    }
}

/// Hero for a hold / duration / distance_time set: mode picker, countdown
/// target or manual entry, and the big ring while a timer is running.
struct TimedSetHero: View {
    @Environment(LiveStore.self) private var live
    let session: LiveSession
    let exercise: LiveExercise
    let field: LiveSession.TimerField
    let measurement: String
    let now: Double
    @Binding var pending: WorkoutSet
    var timedJustFinished = false

    private var mode: TimedSetMode { live.timerMode(for: exercise.item.exerciseId) }
    private var running: PhaseTimer? { session.setTimer }
    private var targetDraft: Double {
        live.countdownPrefill(for: exercise, field: field)
    }

    var body: some View {
        VStack(spacing: 14) {
            TimerModePicker(mode: modeBinding, enabled: running == nil)
            if mode == .manual {
                manualEntry
            } else {
                if mode == .countdown, running == nil {
                    CountdownTargetEditor(seconds: targetBinding)
                }
                ring
                if running == nil {
                    extraSteppers
                }
            }
        }
    }

    private var modeBinding: Binding<TimedSetMode> {
        Binding(
            get: { live.timerMode(for: exercise.item.exerciseId) },
            set: { newValue in
                live.setTimerMode(newValue, for: exercise.item.exerciseId)
                if newValue == .manual { seedManual() }
            }
        )
    }

    private var targetBinding: Binding<Double> {
        Binding(
            get: { live.countdownPrefill(for: exercise, field: field) },
            set: { live.setCountdownTarget($0, for: exercise.item.exerciseId) }
        )
    }

    private var ring: some View {
        let timer = running
        let goal = timer?.countsDown == true ? timer?.targetSec : (field == .hold ? holdGoal : nil)
        let elapsed = timer?.elapsed(now) ?? 0
        let display = timer?.displaySeconds(now) ?? (timedJustFinished ? recorded : (mode == .countdown ? targetDraft : (recorded ?? goal ?? 0)))
        let overtime = timer?.isOvertime(now) == true
        let reached = timer != nil && !overtime && goal.map { elapsed >= $0 } == true
        let progress: Double = {
            if timer == nil { return timedJustFinished ? 1 : 0 }
            if overtime { return 1 }
            if let goal { return min(1, elapsed / max(goal, 1)) }
            return elapsed.truncatingRemainder(dividingBy: 60) / 60
        }()
        let from = overtime ? LV.flame : (reached || timedJustFinished ? LV.lime : LV.gold)
        let to = overtime ? LV.danger : (reached || timedJustFinished ? LV.sky : LV.flame)
        return LVRing(size: 240, stroke: 12, progress: reached || overtime ? 1 : progress, from: from, to: to) {
            Group {
                if overtime {
                    Text("Po czasie")
                } else if timer != nil {
                    if reached { Text("Cel osiągnięty") }
                    else if timer?.countsDown == true { Text("Odliczanie") }
                    else if field == .hold { Text("Trzymasz") }
                    else { Text("Trwa") }
                } else if timedJustFinished {
                    Text("Twój czas")
                } else if mode == .countdown {
                    Text("Odliczanie")
                } else if field == .hold {
                    Text("Cel utrzymania")
                } else {
                    Text("Na czas")
                }
            }
            .lvCaps()
            Text(verbatim: Clock.text(display))
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
                .foregroundStyle(overtime ? AnyShapeStyle(LV.flame) : (reached ? AnyShapeStyle(LV.lime) : AnyShapeStyle(LV.text)))
                .padding(.top, 2)
            if let timer, let goal, !overtime, timer.countsDown || field == .hold {
                Text(verbatim: "/ \(Clock.text(goal))").font(.system(size: 14)).foregroundStyle(LV.muted).monospacedDigit()
            }
        }
    }

    private var manualEntry: some View {
        VStack(spacing: 16) {
            Text("czas").lvCaps()
            Text(verbatim: DurationText.format(max(1, manualSeconds)))
                .font(.system(size: 64, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(LV.heroGradient)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .contentTransition(.numericText())
            CountdownTargetEditor(seconds: manualBinding)
            extraSteppers
        }
        .onAppear { seedManual() }
    }

    private var extraSteppers: some View {
        let extras = SetField.primary(measurement).filter { $0 != .hold && $0 != .duration }
            + ((measurement == "hold" && (pending.weightKg ?? 0) > 0) ? [SetField.weight] : [])
        return Group {
            if !extras.isEmpty {
                HStack(spacing: 10) {
                    ForEach(extras) { item in
                        LVInlineStepper(field: item, set: $pending)
                    }
                }
            }
        }
    }

    private var holdGoal: Double? {
        exercise.target?["targetHoldMax"] ?? exercise.target?["targetHoldMin"] ?? exercise.pending.holdSeconds
    }

    private var recorded: Double {
        switch field {
        case .hold: return exercise.pending.holdSeconds ?? 0
        case .duration: return exercise.pending.durationSeconds.map(Double.init) ?? 0
        }
    }

    private var manualSeconds: Double {
        switch field {
        case .hold: return pending.holdSeconds ?? 0
        case .duration: return pending.durationSeconds.map(Double.init) ?? 0
        }
    }

    private var manualBinding: Binding<Double> {
        Binding(
            get: { max(1, manualSeconds) },
            set: { putManual($0) }
        )
    }

    private func putManual(_ value: Double) {
        let clamped = Limits.durationSeconds.clamp(max(1, value))
        switch field {
        case .hold: pending.holdSeconds = clamped
        case .duration: pending.durationSeconds = clamped.safeInt
        }
    }

    private func seedManual() {
        switch field {
        case .hold:
            if pending.holdSeconds == nil || (pending.holdSeconds ?? 0) < 1 {
                pending.holdSeconds = live.countdownPrefill(for: exercise, field: .hold)
            }
        case .duration:
            if pending.durationSeconds == nil || (pending.durationSeconds ?? 0) < 1 {
                pending.durationSeconds = live.countdownPrefill(for: exercise, field: .duration).safeInt
            }
        }
    }
}
