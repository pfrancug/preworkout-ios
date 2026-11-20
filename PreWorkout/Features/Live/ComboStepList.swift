import SwiftUI

/// One row per combo movement: name + value + −/+ (and a timer on holds).
struct ComboStepList: View {
    let sequence: [String]
    let steps: [WorkoutSetStep]
    let nameOf: (String) -> String
    let measurementOf: (String) -> String
    var runningIndex: Int? = nil
    var runningSeconds: Double? = nil
    var onAdjust: (Int, SetField, Bool) -> Void
    var onToggleTimer: ((Int, SetField) -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(sequence.enumerated()), id: \.offset) { index, id in
                let field = SetField.forMeasurement(measurementOf(id))
                let step = steps[safe: index] ?? WorkoutSetStep(exerciseId: id)
                let running = runningIndex == index
                let value: Double? = running ? runningSeconds : field.stepValue(step)
                row(name: nameOf(id), field: field, value: value, running: running, index: index)
            }
        }
    }

    private func row(name: String, field: SetField, value: Double?, running: Bool, index: Int) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(field == .reps ? "powt." : "s")
                    .lvCaps(LV.muted)
            }
            Spacer(minLength: 8)
            LVStepButton(up: false, size: 44, disabled: (value ?? 0) <= field.range.lowerBound) {
                onAdjust(index, field, false)
            }
            Text(verbatim: running ? Clock.text(value ?? 0) : field.display(value))
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .frame(minWidth: 64)
                .contentTransition(.numericText())
            LVStepButton(up: true, size: 44, disabled: (value ?? 0) >= field.range.upperBound) {
                onAdjust(index, field, true)
            }
            if field != .reps, let onToggleTimer {
                Button {
                    onToggleTimer(index, field)
                } label: {
                    Image(systemName: running ? "stop.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(LVPress())
                .accessibilityLabel(Text(running ? "Stop" : "Start stopera"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
