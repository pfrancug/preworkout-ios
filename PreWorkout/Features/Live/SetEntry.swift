import SwiftUI

/// One number of a set, entered with − / + (same steps and seeds as the web dial).
enum SetField: String, CaseIterable, Identifiable {
    case reps, hold, duration, weight, distance, rpe, rir

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .reps: return "Powtórzenia"
        case .hold: return "Utrzymanie"
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
        case .hold, .duration: return DurationText.format(value)
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
        case .hold: return "czas"
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

/// Tap = one step, hold = repeat. Unlike a Button it gives up as soon as the
/// finger moves more than a few points, so a swipe that starts on − / +
/// never changes the value (the stage swipe still sees the drag).
struct StepPress: ViewModifier {
    var enabled = true
    let action: () -> Void
    @State private var pressed = false
    @State private var cancelled = false
    @State private var repeated = false
    @State private var repeatTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed ? 0.88 : 1)
            .animation(.snappy(duration: 0.15), value: pressed)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        guard enabled else { return }
                        if !pressed && !cancelled {
                            pressed = true
                            repeated = false
                            startRepeat()
                        }
                        if hypot(g.translation.width, g.translation.height) > 10 {
                            cancel()
                        }
                    }
                    .onEnded { _ in
                        let fire = pressed && !cancelled && !repeated && enabled
                        cancel()
                        cancelled = false
                        if fire { action() }
                    }
            )
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if enabled { action() } }
    }

    private func startRepeat() {
        repeatTask?.cancel()
        repeatTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            while !Task.isCancelled && pressed && !cancelled {
                repeated = true
                action()
                try? await Task.sleep(for: .milliseconds(90))
            }
        }
    }

    private func cancel() {
        if pressed { cancelled = true }
        pressed = false
        repeatTask?.cancel()
        repeatTask = nil
    }
}

extension View {
    func stepPress(enabled: Bool = true, action: @escaping () -> Void) -> some View {
        modifier(StepPress(enabled: enabled, action: action))
    }
}

/// Round glass − / +: tap = one step, hold = repeat. `hit` is the touch target
/// (bigger than the circle), so it is easy to hit without touching the number.
struct LVStepButton: View {
    let up: Bool
    var size: CGFloat = 52
    var hit: CGFloat? = nil
    var disabled = false
    let action: () -> Void

    var body: some View {
        Image(systemName: up ? "plus" : "minus")
            .font(.system(size: size * 0.36, weight: .bold))
            .foregroundStyle(LV.text)
            .frame(width: size, height: size)
            .lvGlass(Circle())
            .frame(width: max(size, hit ?? size), height: max(size, hit ?? size))
            .stepPress(enabled: !disabled, action: action)
            .opacity(disabled ? 0.35 : 1)
            .accessibilityLabel(up ? Text("Więcej") : Text("Mniej"))
    }
}

/// Big number dial: − value +. Reps etc.: dragging sideways over the number
/// scrubs it. Time fields: tap the number for hour · minute · second wheels.
struct NumberDial: View {
    let field: SetField
    @Binding var set: WorkoutSet
    var size: CGFloat = 76
    @State private var dragSteps = 0
    @State private var wheels = false

    private var isTime: Bool { field == .hold || field == .duration }

    var body: some View {
        let value = field.get(set)
        VStack(spacing: 6) {
            Text(field.title).lvCaps()
            HStack(spacing: 10) {
                LVStepButton(up: false, hit: 60, disabled: value == nil || (value ?? 0) <= field.range.lowerBound) { step(false) }
                number(value)
                LVStepButton(up: true, hit: 60, disabled: (value ?? 0) >= field.range.upperBound) { step(true) }
            }
            if isTime {
                if wheels {
                    DurationWheel(seconds: Binding(
                        get: { field.get(set) ?? 0 },
                        set: { v in field.put(v > 0 ? v : nil, into: &set) }
                    ))
                    .colorScheme(.dark)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    Text("Dotknij czasu, aby ustawić godziny, minuty i sekundy")
                        .font(.system(size: 12)).foregroundStyle(LV.faint)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: field.get(set))
    }

    @ViewBuilder
    private func number(_ value: Double?) -> some View {
        let text = Text(verbatim: field.display(value))
            .font(.system(size: size, weight: .black, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(LV.heroGradient)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .frame(minWidth: 120)
            .contentTransition(.numericText())
            .contentShape(Rectangle())
        if isTime {
            text.onTapGesture { withAnimation(LV.spring) { wheels.toggle() } }
                .accessibilityAddTraits(.isButton)
        } else {
            text.gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { g in
                        let steps = Int(g.translation.width / 18)
                        while dragSteps < steps { dragSteps += 1; step(true) }
                        while dragSteps > steps { dragSteps -= 1; step(false) }
                    }
                    .onEnded { _ in dragSteps = 0 }
            )
        }
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
            let canDown = !(value == nil || (value ?? 0) <= field.range.lowerBound)
            Image(systemName: "minus").frame(width: 48, height: 48)
                .stepPress(enabled: canDown) { withAnimation(.snappy) { field.bump(&set, up: false) } }
                .opacity(canDown ? 1 : 0.35)
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
            let canUp = (value ?? 0) < field.range.upperBound
            Image(systemName: "plus").frame(width: 48, height: 48)
                .stepPress(enabled: canUp) { withAnimation(.snappy) { field.bump(&set, up: true) } }
                .opacity(canUp ? 1 : 0.35)
                .accessibilityLabel(Text("Więcej"))
        }
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(LV.text)
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
        if set.stepsSummary == nil, let hold = set.holdSeconds { parts.append(DurationText.format(hold)) }
        if let distance = set.distanceM { parts.append("\(distance.short()) m") }
        if set.stepsSummary == nil, let duration = set.durationSeconds { parts.append(DurationText.format(duration)) }
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
        let lo = target["targetHoldMin"], hi = target["targetHoldMax"]
        switch (lo, hi) {
        case let (l?, h?) where l != h: parts.append("\(DurationText.format(l))–\(DurationText.format(h))")
        case let (l?, _): parts.append(DurationText.format(l))
        case let (nil, h?): parts.append(DurationText.format(h))
        default: break
        }
        if let kg = target["targetWeightKg"], kg > 0 { parts.append("+\(kg.short(2)) kg") }
        if let rpe = target["targetRpe"] { parts.append("RPE \(rpe.short())") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
