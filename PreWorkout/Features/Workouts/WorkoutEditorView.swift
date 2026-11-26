import SwiftUI

/// Sheet: create or edit a workout (session fields, exercises, sets).
struct WorkoutEditorView: View {
    /// nil = new workout
    let workoutId: String?
    let onSaved: (Workout) -> Void

    @Environment(AppState.self) private var appState
    @Environment(ExerciseStore.self) private var exercises
    @Environment(\.dismiss) private var dismiss
    @State private var draft: WorkoutDraft
    @State private var pickingExercise = false
    @State private var saving = false
    @State private var error: String?
    @State private var confirmDiscard = false
    @State private var saved = 0
    /// Stable id for a retried create (the API dedupes by id).
    @State private var createId = newId()
    private let original: WorkoutDraft

    init(workoutId: String?, draft: WorkoutDraft, onSaved: @escaping (Workout) -> Void) {
        self.workoutId = workoutId
        self.onSaved = onSaved
        _draft = State(initialValue: draft)
        original = draft
    }

    var body: some View {
        NavigationStack {
            Form {
                sessionSection

                ForEach($draft.exercises) { $exercise in
                    exerciseSection($exercise)
                }

                Section {
                    Button("Dodaj ćwiczenie", systemImage: "plus.circle.fill") { pickingExercise = true }
                }

                Section("Notatki") {
                    TextField("Jak poszło?", text: $draft.notes, axis: .vertical)
                        .maxLength($draft.notes, 4000)
                        .lineLimit(3...10)
                }

                if let error {
                    Section { ErrorText(message: error) }
                }
            }
            .navigationTitle(workoutId == nil ? Text("Nowy trening") : Text("Edytuj trening"))
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") {
                        if draft == original { dismiss() } else { confirmDiscard = true }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Zapisz") { Task { await save() } }
                            .bold()
                    }
                }
            }
            .alert("Odrzucić zmiany?", isPresented: $confirmDiscard) {
                Button("Odrzuć zmiany", role: .destructive) { dismiss() }
                Button("Anuluj", role: .cancel) {}
            }
            .sheet(isPresented: $pickingExercise) {
                ExercisePickerView { exercise in
                    var set = WorkoutSet()
                    if exercise.measurement == "reps_weight" { set.weightKg = 0 }
                    draft.exercises.append(DraftExercise(exerciseId: exercise.id, sets: [set]))
                }
            }
            .interactiveDismissDisabled(draft != original)
            .sensoryFeedback(.success, trigger: saved)
            .sensoryFeedback(.error, trigger: error) { _, new in new != nil }
            .task {
                await exercises.loadIfNeeded()
                await appState.loadCategoriesIfNeeded()
            }
        }
    }

    private var sessionSection: some View {
        Section {
            DatePicker("Data", selection: $draft.date, displayedComponents: .date)
            TextField("Tytuł (opcjonalnie)", text: $draft.title)
                .maxLength($draft.title, 120)
            Picker("Kategoria", selection: $draft.categoryId) {
                Text("Brak").tag(String?.none)
                ForEach(appState.categories.filter { $0.archived != true || $0.id == draft.categoryId }) { category in
                    Text(verbatim: "\(category.icon) \(category.name)").tag(Optional(category.id))
                }
            }
            IntField("Czas trwania", value: $draft.durationMin, unit: "min", limit: Limits.sessionMinutes)
            DecimalField("RPE sesji", value: $draft.rpe, limit: Limits.rpe)
        }
    }

    private func exerciseSection(_ exercise: Binding<DraftExercise>) -> some View {
        let value = exercise.wrappedValue
        let measurement = exercises.byId[value.exerciseId]?.measurement ?? "reps"
        return Section {
            Toggle("Sesja (blok czasu)", isOn: Binding(
                get: { exercise.wrappedValue.isSession },
                set: { on in
                    exercise.wrappedValue.kind = on ? "session" : "sets"
                    if on {
                        if exercise.wrappedValue.sets.isEmpty {
                            exercise.wrappedValue.sets = [DraftSet(value: WorkoutSet())]
                        } else if exercise.wrappedValue.sets.count > 1 {
                            exercise.wrappedValue.sets = [exercise.wrappedValue.sets[0]]
                        }
                    }
                }
            ))
            if value.isSession {
                sessionFields(exercise)
            } else {
                ForEach(Array(exercise.sets.enumerated()), id: \.element.wrappedValue.id) { item in
                    setRow(item.element, number: item.offset + 1, measurement: measurement, sequence: value.sequence)
                }
                .onDelete { offsets in exercise.wrappedValue.sets.remove(atOffsets: offsets) }

                Button("Dodaj serię", systemImage: "plus") {
                    let template = exercise.wrappedValue.sets.last?.value ?? WorkoutSet()
                    exercise.wrappedValue.sets.append(DraftSet(value: template))
                }
                .disabled(value.sets.count >= 50)
            }

            TextField("Wariant (opcjonalnie)", text: exercise.variant.orEmpty)

                .maxLength(exercise.variant.orEmpty, 200)
            TextField("Notatka do ćwiczenia", text: exercise.notes, axis: .vertical)
                .maxLength(exercise.notes, 1000)
        } header: {
            HStack {
                Text(comboTitle(value))
                Spacer()
                Menu {
                    Button("Przenieś wyżej", systemImage: "arrow.up") { move(value.id, by: -1) }
                        .disabled(draft.exercises.first?.id == value.id)
                    Button("Przenieś niżej", systemImage: "arrow.down") { move(value.id, by: 1) }
                        .disabled(draft.exercises.last?.id == value.id)
                    Button("Usuń ćwiczenie", systemImage: "trash", role: .destructive) {
                        draft.exercises.removeAll { $0.id == value.id }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .imageScale(.large)
                }
            }
            .textCase(nil)
        }
    }

    private func sessionFields(_ exercise: Binding<DraftExercise>) -> some View {
        let set = Binding(
            get: { exercise.wrappedValue.sets.first?.value ?? WorkoutSet() },
            set: { new in
                if exercise.wrappedValue.sets.isEmpty {
                    exercise.wrappedValue.sets = [DraftSet(value: new)]
                } else {
                    exercise.wrappedValue.sets[0].value = new
                }
            }
        )
        return Group {
            DurationField("Czas", wholeSeconds: set.durationSeconds)
            IntField("Próby", value: set.attempts, limit: Limits.attempts)
            TextField("Notatka (opcjonalnie)", text: set.notes, axis: .vertical)
                .maxLength(set.notes, 500)
        }
    }

    private func comboTitle(_ exercise: DraftExercise) -> String {
        let ids = exercise.sequence.count > 1 ? exercise.sequence : [exercise.exerciseId]
        return ids.map { exercises.name($0) }.joined(separator: " → ")
    }

    private func setRow(_ set: Binding<DraftSet>, number: Int, measurement: String, sequence: [String]) -> some View {
        NavigationLink {
            SetEditorView(set: set.value, measurement: measurement, number: number, sequence: sequence, nameOf: { exercises.name($0) }, measurementOf: { exercises.byId[$0]?.measurement ?? "reps" })
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "\(number).")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 26, alignment: .leading)
                Text(SetFormat.summary(set.wrappedValue.value))
                Spacer()
                if set.wrappedValue.value.isWarmup { Tag("Rozgrzewka", color: .orange) }
            }
        }
    }

    private func move(_ id: String, by offset: Int) {
        guard let index = draft.exercises.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard draft.exercises.indices.contains(target) else { return }
        draft.exercises.swapAt(index, target)
    }

    private func save() async {
        if let message = draft.validationError {
            error = message
            return
        }
        saving = true
        error = nil
        defer { saving = false }
        do {
            let person = appState.activePersonId
            let workout: Workout
            if let workoutId {
                workout = try await APIClient.shared.updateWorkout(workoutId, draft.input(id: workoutId), person: person)
            } else {
                workout = try await APIClient.shared.createWorkout(draft.input(id: createId), person: person)
            }
            saved += 1
            Analytics.send(workoutId == nil ? "Workout.created" : "Workout.edited")
            onSaved(workout)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// One set: result fields for the exercise's measurement, load, intensity, notes.
struct SetEditorView: View {
    @Binding var set: WorkoutSet
    let measurement: String
    let number: Int
    var sequence: [String] = []
    var nameOf: (String) -> String = { $0 }
    var measurementOf: (String) -> String = { _ in "reps" }

    var body: some View {
        Form {
            Section("Wynik") {
                if sequence.count > 1 {
                    ForEach(Array(sequence.enumerated()), id: \.offset) { index, id in
                        let field = SetField.forMeasurement(measurementOf(id))
                        let label = nameOf(id)
                        stepField(label: label, field: field, index: index)
                    }
                } else {
                switch measurement {
                case "hold":
                    DurationField("Czas utrzymania", seconds: $set.holdSeconds)
                case "reps_weight":
                    IntField("Powtórzenia", value: $set.reps, limit: Limits.reps)
                    DecimalField("Ciężar", value: $set.weightKg, unit: "kg", limit: Limits.loadKg)
                case "distance_time":
                    DecimalField("Dystans", value: $set.distanceM, unit: "m", limit: Limits.distanceM)
                    DurationField("Czas", wholeSeconds: $set.durationSeconds)
                default:
                    IntField("Powtórzenia", value: $set.reps, limit: Limits.reps)
                }
                }
                Toggle("Seria rozgrzewkowa", isOn: $set.isWarmup)
            }

            Section {
                if measurement != "reps_weight" {
                    DecimalField("Dodatkowy ciężar", value: $set.weightKg, unit: "kg", limit: Limits.loadKg)
                }
                Picker("Asysta", selection: $set.assistance) {
                    ForEach(Labels.assistance, id: \.self) { value in
                        Text(Labels.assistance(value)).tag(value)
                    }
                }
                if set.assistance != "none" {
                    TextField("Opis asysty (np. zielona guma)", text: $set.assistanceNote)
                        .maxLength($set.assistanceNote, 200)
                }
            } header: {
                Text("Obciążenie")
            } footer: {
                Text("Dodatkowy ciężar to obciążenie ponad masę ciała (pas, kamizelka).")
            }

            Section {
                DecimalField("RPE", value: $set.rpe, limit: Limits.rpe)
                IntField("RIR", value: $set.rir, limit: Limits.rir)
                DurationField("Przerwa po serii", wholeSeconds: $set.restSeconds)
            } header: {
                Text("Intensywność")
            } footer: {
                Text("RPE 0–10 (wysiłek), RIR 0–10 (powtórzenia w zapasie).")
            }

            Section("Więcej") {
                if measurement != "reps" && measurement != "reps_weight" {
                    IntField("Powtórzenia", value: $set.reps, limit: Limits.reps)
                }
                if measurement != "hold" {
                    DurationField("Czas utrzymania", seconds: $set.holdSeconds)
                }
                TextField("Notatka", text: $set.notes, axis: .vertical)
                    .maxLength($set.notes, 500)
            }
        }
        .navigationTitle(String(localized: "Seria \(number)"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: set.steps) { _, _ in
            set.applySteps(sequence: sequence)
        }
    }

    @ViewBuilder
    private func stepField(label: String, field: SetField, index: Int) -> some View {
        let step = set.steps[safe: index] ?? WorkoutSetStep(exerciseId: sequence[safe: index] ?? "")
        switch field {
        case .hold:
            DurationField(LocalizedStringKey(label), seconds: Binding(
                get: { step.holdSeconds },
                set: { updateStep(index: index, field: field, hold: $0) }
            ))
        case .duration:
            DurationField(LocalizedStringKey(label), wholeSeconds: Binding(
                get: { step.durationSeconds },
                set: { updateStep(index: index, field: field, duration: $0) }
            ))
        default:
            IntField(LocalizedStringKey(label), value: Binding(
                get: { step.reps },
                set: { updateStep(index: index, field: field, reps: $0) }
            ), limit: Limits.reps)
        }
    }

    private func updateStep(index: Int, field: SetField, reps: Int? = nil, hold: Double? = nil, duration: Int? = nil) {
        var steps = set.steps
        if steps.isEmpty {
            steps = sequence.map { WorkoutSet.defaultStep($0, measurementOf($0), hint: set) }
            // defaultStep(hint: WorkoutSet) fills last only; for editing, start from last-value on last step.
        }
        while steps.count < sequence.count {
            let id = sequence[steps.count]
            steps.append(WorkoutSetStep(exerciseId: id))
        }
        guard steps.indices.contains(index) else { return }
        switch field {
        case .hold: steps[index].holdSeconds = hold
        case .duration: steps[index].durationSeconds = duration
        default: steps[index].reps = reps
        }
        set.steps = steps
        set.applySteps(sequence: sequence)
    }
}
