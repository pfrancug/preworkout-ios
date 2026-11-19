import SwiftUI

/// Sheet: create or edit a custom exercise.
struct ExerciseEditorView: View {
    /// nil = new custom exercise
    let exercise: Exercise?

    @Environment(ExerciseStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var input: ExerciseInput
    @State private var muscles: String
    @State private var musclesPrimary: String
    @State private var equipment: String
    @State private var variants: String
    @State private var picking: ChainSlot?
    @State private var saving = false
    @State private var error: String?
    @State private var saved = 0

    private enum ChainSlot: String, Identifiable {
        case prev, next
        var id: String { rawValue }
    }

    init(exercise: Exercise?) {
        self.exercise = exercise
        let input = exercise.map(ExerciseInput.init) ?? ExerciseInput()
        _input = State(initialValue: input)
        _muscles = State(initialValue: input.muscles.joined(separator: ", "))
        _musclesPrimary = State(initialValue: input.musclesPrimary.joined(separator: ", "))
        _equipment = State(initialValue: input.equipment.joined(separator: ", "))
        _variants = State(initialValue: input.variants.joined(separator: "\n"))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nazwa", text: $input.name)
                    Picker("Rodzaj", selection: $input.modality) {
                        ForEach(Labels.modalities, id: \.self) { Text(Labels.modality($0)).tag($0) }
                    }
                    Picker("Kategoria", selection: $input.category) {
                        ForEach(Labels.categories, id: \.self) { Text(Labels.category($0)).tag($0) }
                    }
                    Picker("Poziom", selection: $input.difficulty) {
                        Text("Nie podano").tag(String?.none)
                        ForEach(Labels.difficulties, id: \.self) { Text(Labels.difficulty($0)).tag(Optional($0)) }
                    }
                    Picker("Pomiar", selection: $input.measurement) {
                        ForEach(Labels.measurements, id: \.self) { Text(Labels.measurement($0)).tag($0) }
                    }
                }

                Section {
                    TextField("Wszystkie mięśnie", text: $muscles, axis: .vertical)
                    TextField("Główne mięśnie", text: $musclesPrimary, axis: .vertical)
                    TextField("Sprzęt", text: $equipment, axis: .vertical)
                } header: {
                    Text("Mięśnie i sprzęt")
                } footer: {
                    Text("Oddzielaj przecinkami, np. lats, biceps.")
                }

                Section {
                    TextField("Rodzina (np. pull-up)", text: $input.family.orEmpty)
                    chainRow("Łatwiejsze", id: input.prevExerciseId, slot: .prev)
                    chainRow("Trudniejsze", id: input.nextExerciseId, slot: .next)
                } header: {
                    Text("Progresja")
                }

                Section {
                    TextField("Jeden wariant w linii", text: $variants, axis: .vertical)
                        .lineLimit(2...8)
                } header: {
                    Text("Warianty")
                }

                Section("Opis") {
                    TextField("Technika, wskazówki (Markdown)", text: $input.description, axis: .vertical)
                        .lineLimit(4...14)
                }

                if exercise != nil {
                    Section {
                        Toggle("Zarchiwizowane", isOn: $input.archived)
                    } footer: {
                        Text("Zarchiwizowane ćwiczenie zostaje w historii, ale nie pojawia się przy wyborze.")
                    }
                }

                if let error {
                    Section { ErrorText(message: error) }
                }
            }
            .navigationTitle(exercise == nil ? Text("Nowe ćwiczenie") : Text("Edytuj ćwiczenie"))
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Zapisz") { Task { await save() } }
                            .bold()
                            .disabled(input.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .sheet(item: $picking) { slot in
                ExercisePickerView { picked in
                    switch slot {
                    case .prev: input.prevExerciseId = picked.id
                    case .next: input.nextExerciseId = picked.id
                    }
                }
            }
            .sensoryFeedback(.success, trigger: saved)
            .task { await store.loadIfNeeded() }
        }
    }

    private func chainRow(_ title: LocalizedStringKey, id: String?, slot: ChainSlot) -> some View {
        HStack {
            Button {
                picking = slot
            } label: {
                LabeledContent(title) {
                    Text(id.map(store.name) ?? String(localized: "Brak"))
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.primary)
            if id != nil {
                Button {
                    switch slot {
                    case .prev: input.prevExerciseId = nil
                    case .next: input.nextExerciseId = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private static func list(_ raw: String, separator: Character) -> [String] {
        raw.split(separator: separator)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func save() async {
        var body = input
        body.name = input.name.trimmingCharacters(in: .whitespaces)
        body.muscles = Self.list(muscles, separator: ",")
        body.musclesPrimary = Self.list(musclesPrimary, separator: ",")
        // Primary muscles are a subset of all muscles.
        for muscle in body.musclesPrimary where !body.muscles.contains(muscle) { body.muscles.append(muscle) }
        body.equipment = Self.list(equipment, separator: ",")
        body.variants = Self.list(variants, separator: "\n")
        body.family = body.family?.trimmingCharacters(in: .whitespaces)
        if body.family?.isEmpty == true { body.family = nil }

        if body.name.count > 120 { error = String(localized: "Nazwa może mieć najwyżej 120 znaków."); return }
        if body.muscles.count > 20 || body.equipment.count > 20 || body.variants.count > 20 {
            error = String(localized: "Każda lista może mieć najwyżej 20 pozycji.")
            return
        }
        if body.description.count > 2000 { error = String(localized: "Opis może mieć najwyżej 2000 znaków."); return }
        if let id = exercise?.id, body.prevExerciseId == id || body.nextExerciseId == id {
            error = String(localized: "Ćwiczenie nie może wskazywać samego siebie.")
            return
        }

        saving = true
        error = nil
        defer { saving = false }
        do {
            let result: Exercise
            if let id = exercise?.id {
                result = try await APIClient.shared.updateExercise(id, body)
            } else {
                result = try await APIClient.shared.createExercise(body)
            }
            store.upsert(result)
            saved += 1
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
