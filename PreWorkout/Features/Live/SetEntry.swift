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

/// − value + row; holding a button repeats.
struct StepperRow: View {
    let field: SetField
    @Binding var set: WorkoutSet
    var large = false

    var body: some View {
        let value = field.get(set)
        HStack(spacing: 12) {
            Text(field.title)
                .font(large ? .subheadline : .body)
                .foregroundStyle(large ? .secondary : .primary)
            Spacer(minLength: 8)
            stepControl("minus", delta: -field.step, disabled: value == nil || (value ?? 0) <= field.range.lowerBound)
            Text(verbatim: field.format(value))
                .font(large ? .title.weight(.semibold) : .title3.weight(.medium))
                .monospacedDigit()
                .frame(minWidth: large ? 84 : 64)
                .contentTransition(.numericText())
            stepControl("plus", delta: field.step, disabled: (value ?? 0) >= field.range.upperBound)
        }
        .padding(.vertical, large ? 4 : 0)
    }

    private func stepControl(_ icon: String, delta: Double, disabled: Bool) -> some View {
        Button {
            withAnimation(.snappy) { change(by: delta) }
        } label: {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .frame(width: large ? 44 : 36, height: large ? 44 : 36)
                .background(.tint.opacity(0.15), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .buttonRepeatBehavior(.enabled)
        .disabled(disabled)
        .sensoryFeedback(.selection, trigger: field.get(set))
    }

    private func change(by delta: Double) {
        let current = field.get(set)
        let next: Double
        if let current {
            next = min(field.range.upperBound, max(field.range.lowerBound, current + delta))
        } else {
            next = delta > 0 ? max(field.seed, field.range.lowerBound + (field.seed == 0 ? field.step : 0)) : field.range.lowerBound
        }
        field.put(next, into: &set)
    }
}

/// Every editable field of a set (used for logging and for editing a logged set).
struct SetFieldsView: View {
    let measurement: String
    @Binding var set: WorkoutSet
    var showExtras: Bool

    var body: some View {
        ForEach(SetField.primary(measurement)) { field in
            StepperRow(field: field, set: $set, large: true)
        }
        if showExtras {
            ForEach(SetField.extra(measurement)) { field in
                StepperRow(field: field, set: $set)
            }
            Toggle("Rozgrzewka", isOn: $set.isWarmup)
            TextField("Notatka do serii", text: $set.notes, axis: .vertical)
        }
    }
}

/// Sheet: edit or delete a logged set.
struct LiveSetEditor: View {
    let title: String
    let setNumber: Int
    let measurement: String
    @State var set: WorkoutSet
    let onSave: (WorkoutSet) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SetFieldsView(measurement: measurement, set: $set, showExtras: true)
                } header: {
                    Text(verbatim: title)
                }
                Section {
                    Button("Usuń serię", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Seria \(setNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Anuluj") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zapisz") {
                        onSave(set)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

enum LiveFormat {
    /// "8 × +10 kg", "8 powt.", "0:30", "400 m · 2:10": a logged set in words.
    static func set(_ set: WorkoutSet) -> String {
        var parts: [String] = []
        let weight = set.weightKg.flatMap { $0 > 0 ? "+\($0.short(2)) kg" : nil }
        if let reps = set.reps {
            parts.append(weight.map { "\(reps) × \($0)" } ?? String(localized: "\(reps) powt."))
        } else if let weight {
            parts.append(weight)
        }
        if let hold = set.holdSeconds { parts.append(hold < 60 ? "\(hold.short(0)) s" : Clock.text(hold)) }
        if let distance = set.distanceM { parts.append("\(distance.short()) m") }
        if let duration = set.durationSeconds { parts.append(Clock.text(Double(duration))) }
        return parts.isEmpty ? "•" : parts.joined(separator: " · ")
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
