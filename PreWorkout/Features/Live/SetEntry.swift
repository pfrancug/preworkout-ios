import SwiftUI

/// One number of a set, entered with − / + (same steps and seeds as the web dial).
enum SetField: String, CaseIterable, Identifiable {
    case reps, hold, duration, weight, distance, rpe, rir

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .reps: return "Powtórzenia"
        case .hold: return "Utrzymanie (s)"
        case .duration: return "Czas"
        case .weight: return "Obciążenie (+kg)"
        case .distance: return "Dystans (m)"
        case .rpe: return "RPE"
        case .rir: return "RIR"
        }
    }

    var step: Double {
        switch self {
        case .reps, .hold, .rir: return 1
        case .duration: return 5
        case .weight: return 1.25
        case .distance: return 10
        case .rpe: return 0.5
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .reps: return 0...300
        case .hold: return 0...3600
        case .duration: return 0...36000
        case .weight: return 0...400
        case .distance: return 0...100000
        case .rpe: return 1...10
        case .rir: return 0...10
        }
    }

    /// First value when the field is still empty.
    var seed: Double {
        switch self {
        case .reps: return 8
        case .hold: return 30
        case .duration: return 60
        case .weight: return 0
        case .distance: return 100
        case .rpe: return 8
        case .rir: return 2
        }
    }

    func get(_ set: WorkoutSet) -> Double? {
        switch self {
        case .reps: return set.reps.map(Double.init)
        case .hold: return set.holdSeconds
        case .duration: return set.durationSeconds.map(Double.init)
        case .weight: return set.weightKg
        case .distance: return set.distanceM
        case .rpe: return set.rpe
        case .rir: return set.rir.map(Double.init)
        }
    }

    func put(_ value: Double?, into set: inout WorkoutSet) {
        switch self {
        case .reps: set.reps = value.map { Int($0) }
        case .hold: set.holdSeconds = value
        case .duration: set.durationSeconds = value.map { Int($0) }
        // 0 kg = no extra load
        case .weight: set.weightKg = (value ?? 0) == 0 ? nil : value
        case .distance: set.distanceM = value
        case .rpe: set.rpe = value
        case .rir: set.rir = value.map { Int($0) }
        }
    }

    func format(_ value: Double?) -> String {
        guard let value else { return "–" }
        switch self {
        case .hold: return value < 60 ? value.short(0) : Clock.text(value)
        case .duration: return Clock.text(value)
        case .weight: return value.short(2)
        default: return value.short(1)
        }
    }

    /// Main numbers per exercise measurement; the rest go under "More".
    static func primary(_ measurement: String) -> [SetField] {
        switch measurement {
        case "hold": return [.hold]
        case "reps_weight": return [.reps, .weight]
        case "distance_time": return [.distance, .duration]
        default: return [.reps]
        }
    }

    static func extra(_ measurement: String) -> [SetField] {
        switch measurement {
        case "hold": return [.weight, .rpe]
        case "reps_weight": return [.rpe, .rir]
        case "distance_time": return [.rpe]
        default: return [.weight, .rpe, .rir]
        }
    }
}

extension SetField {
    /// One step up or down; an empty field starts from its seed.
    static func forMeasurement(_ measurement: String) -> SetField {
        switch measurement {
        case "hold": return .hold
        case "distance_time": return .duration
        default: return .reps
        }
    }

    func stepValue(_ step: WorkoutSetStep) -> Double? {
        switch self {
        case .reps: return step.reps.map(Double.init)
        case .hold: return step.holdSeconds
        case .duration: return step.durationSeconds.map(Double.init)
        default: return nil
        }
    }

    func putStep(_ value: Double?, into step: inout WorkoutSetStep) {
        switch self {
        case .reps: step.reps = value.map { Int($0) }
        case .hold: step.holdSeconds = value
        case .duration: step.durationSeconds = value.map { Int($0) }
        default: break
        }
    }

    func bumpStep(_ step: inout WorkoutSetStep, up: Bool) {
        let delta = up ? self.step : -self.step
        let current = stepValue(step)
        let next: Double
        if let current {
            next = min(range.upperBound, max(range.lowerBound, current + delta))
        } else {
            next = up ? 1 : range.lowerBound
        }
        putStep(next, into: &step)
    }

    func bump(_ set: inout WorkoutSet, up: Bool) {
        let delta = up ? self.step : -self.step
        let next: Double
        if let current = get(set) {
            next = min(range.upperBound, max(range.lowerBound, current + delta))
        } else {
            next = up ? max(seed, range.lowerBound + (seed == 0 ? step : 0)) : range.lowerBound
        }
        put(next, into: &set)
    }

    var unit: LocalizedStringKey? {
        switch self {
        case .reps: return "powt."
        case .hold: return "sekundy"
        case .duration: return "czas"
        case .weight: return "kg"
        case .distance: return "metry"
        case .rpe, .rir: return nil
        }
    }

    /// Value shown big (weight with a "+").
    func display(_ value: Double?) -> String {
        guard let value else { return "–" }
        return self == .weight && value > 0 ? "+" + format(value) : format(value)
    }
}

/// Small round glass − / + (repeats while held).
struct LVStepButton: View {
    let up: Bool
    var size: CGFloat = 52
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: up ? "plus" : "minus")
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(LV.text)
                .frame(width: size, height: size)
                .lvGlass(Circle())
        }
        .buttonStyle(LVPress(scale: 0.88))
        .buttonRepeatBehavior(.enabled)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .accessibilityLabel(up ? Text("Więcej") : Text("Mniej"))
    }
}

/// Big number dial: − value +, and dragging sideways over the number scrubs it.
struct NumberDial: View {
    let field: SetField
    @Binding var set: WorkoutSet
    var size: CGFloat = 76
    @State private var dragSteps = 0

    var body: some View {
        let value = field.get(set)
        VStack(spacing: 6) {
            Text(field.title).lvCaps()
            HStack(spacing: 14) {
                LVStepButton(up: false, disabled: value == nil || (value ?? 0) <= field.range.lowerBound) { step(false) }
                Text(verbatim: field.display(value))
                    .font(.system(size: size, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(LV.heroGradient)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(minWidth: 120)
                    .contentTransition(.numericText())
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { g in
                                let steps = Int(g.translation.width / 18)
                                while dragSteps < steps { dragSteps += 1; step(true) }
                                while dragSteps > steps { dragSteps -= 1; step(false) }
                            }
                            .onEnded { _ in dragSteps = 0 }
                    )
                LVStepButton(up: true, disabled: (value ?? 0) >= field.range.upperBound) { step(true) }
            }
        }
        .sensoryFeedback(.selection, trigger: field.get(set))
    }

    private func step(_ up: Bool) {
        withAnimation(.snappy) { field.bump(&set, up: up) }
    }
}

/// Compact − value + capsule (secondary numbers: weight, RPE, RIR…).
struct LVInlineStepper: View {
    let field: SetField
    @Binding var set: WorkoutSet
    var showTitle = true

    var body: some View {
        let value = field.get(set)
        HStack(spacing: 0) {
            Button { withAnimation(.snappy) { field.bump(&set, up: false) } } label: {
                Image(systemName: "minus").frame(width: 44, height: 44)
            }
            .buttonRepeatBehavior(.enabled)
            .disabled(value == nil || (value ?? 0) <= field.range.lowerBound)
            .accessibilityLabel(Text("Mniej"))
            VStack(spacing: 0) {
                Text(verbatim: field == .weight ? "\(field.display(value ?? 0)) kg" : field.display(value))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if showTitle {
                    Text(field.title).font(.system(size: 10, weight: .medium)).foregroundStyle(LV.faint)
                }
            }
            .frame(minWidth: 72)
            Button { withAnimation(.snappy) { field.bump(&set, up: true) } } label: {
                Image(systemName: "plus").frame(width: 44, height: 44)
            }
            .buttonRepeatBehavior(.enabled)
            .disabled((value ?? 0) >= field.range.upperBound)
            .accessibilityLabel(Text("Więcej"))
        }
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(LV.text)
        .buttonStyle(LVPress(scale: 0.85))
        .lvGlass(Capsule())
        .sensoryFeedback(.selection, trigger: field.get(set))
    }
}

/// Sheet: the numbers of one set, big dials first, extras below.
/// Used to adjust the set about to be done, to log one, or to fix a logged one.
struct LiveLogSheet: View {
    enum Mode: Equatable { case pending, log, edit }

    let mode: Mode
    let title: String
    let setNumber: Int
    let measurement: String
    @State var set: WorkoutSet
    var sequence: [String] = []
    var nameOf: (String) -> String = { $0 }
    var measurementOf: (String) -> String = { _ in "reps" }
    let onSave: (WorkoutSet) -> Void
    var onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var extras = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 6) {
                    Group {
                        if mode == .edit {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(LV.lime)
                                Text("Zrobiona seria \(setNumber)")
                            }
                        } else {
                            Text("Teraz: seria \(setNumber)")
                        }
                    }
                    .lvCaps(mode == .edit ? LV.lime : LV.ember)
                    Text(verbatim: title)
                        .font(.system(size: 22, weight: .bold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(LV.text)
                }
                .padding(.top, 28)

                if sequence.count > 1 {
                    ComboStepList(
                        sequence: sequence,
                        steps: set.steps,
                        nameOf: nameOf,
                        measurementOf: measurementOf,
                        onAdjust: { index, field, up in
                            var steps = set.steps
                            if steps.indices.contains(index) {
                                field.bumpStep(&steps[index], up: up)
                                set.steps = steps
                                set.applySteps(sequence: sequence)
                            }
                        }
                    )
                } else {
                    ForEach(SetField.primary(measurement)) { field in
                        NumberDial(field: field, set: $set)
                    }
                }

                if extras {
                    VStack(spacing: 12) {
                        ForEach(SetField.extra(measurement)) { field in
                            LVInlineStepper(field: field, set: $set)
                        }
                        Toggle("Rozgrzewka", isOn: $set.isWarmup)
                            .tint(LV.ember)
                            .padding(.horizontal, 18)
                            .frame(height: 50)
                            .lvGlass(Capsule())
                        TextField("Notatka do serii", text: $set.notes, axis: .vertical)
                            .padding(14)
                            .lvGlass(RoundedRectangle(cornerRadius: 18))
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    LVPill(action: { withAnimation(LV.spring) { extras = true } }) {
                        Image(systemName: "slider.horizontal.3")
                        Text("Więcej: RPE, rozgrzewka, notatka")
                    }
                }

                VStack(spacing: 10) {
                    LVCta(mood: mode == .edit ? .done : .active) {
                        var saved = set
                        saved.applySteps(sequence: sequence)
                        onSave(saved)
                        dismiss()
                    } content: {
                        Image(systemName: "checkmark")
                        switch mode {
                        case .pending: Text("Gotowe")
                        case .log: Text("Zapisz serię \(setNumber)")
                        case .edit: Text("Zapisz zmiany")
                        }
                    }
                    if let onDelete {
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            Label("Usuń serię", systemImage: "trash")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(LV.danger)
                                .frame(height: 44)
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
        }
        .foregroundStyle(LV.text)
        .lvSheet(mode == .edit ? [.large] : [.medium, .large])
    }
}

enum LiveFormat {
    /// "8 × +10 kg", "8 powt.", "0:30", "400 m · 2:10": a logged set in words.
    static func set(_ set: WorkoutSet) -> String {
        var parts: [String] = []
        let weight = set.weightKg.flatMap { $0 > 0 ? "+\($0.short(2)) kg" : nil }
        if let stepped = set.stepsSummary {
            parts.append(weight.map { "\(stepped) × \($0)" } ?? stepped)
        } else if let reps = set.reps {
            parts.append(weight.map { "\(reps) × \($0)" } ?? String(localized: "\(reps) powt."))
        } else if let weight {
            parts.append(weight)
        }
        if let hold = set.holdSeconds { parts.append(hold < 60 ? "\(hold.short(0)) s" : Clock.text(hold)) }
        if let distance = set.distanceM { parts.append("\(distance.short()) m") }
        if let duration = set.durationSeconds { parts.append(Clock.text(Double(duration))) }
        return parts.isEmpty ? "•" : parts.joined(separator: " · ")
    }

    /// The prepared next set in words, nil when empty.
    static func pendingText(_ e: LiveExercise) -> String? {
        let text = set(e.pending)
        return text == "•" ? nil : text
    }

    /// Plan target in words, nil without a target.
    static func target(_ target: JSONValue?) -> String? {
        guard let target else { return nil }
        var parts: [String] = []
        let range = { (lo: Double?, hi: Double?) -> String? in
            switch (lo, hi) {
            case let (l?, h?) where l != h: return "\(l.short(0))–\(h.short(0))"
            case let (l?, _): return l.short(0)
            case let (nil, h?): return h.short(0)
            default: return nil
            }
        }
        if let repsText = range(target["targetRepsMin"], target["targetRepsMax"]) {
            parts.append(String(localized: "\(repsText) powt. w serii"))
        }
        if let hold = range(target["targetHoldMin"], target["targetHoldMax"]) { parts.append("\(hold) s") }
        if let kg = target["targetWeightKg"], kg > 0 { parts.append("+\(kg.short(2)) kg") }
        if let rpe = target["targetRpe"] { parts.append("RPE \(rpe.short())") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
