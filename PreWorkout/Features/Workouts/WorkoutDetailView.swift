import SwiftUI

struct WorkoutDetailView: View {
    let workoutId: String
    /// Called after an edit or delete so the list can refresh.
    var onChange: () async -> Void = {}

    @Environment(AppState.self) private var appState
    @Environment(ExerciseStore.self) private var exercises
    @Environment(\.dismiss) private var dismiss
    @State private var state: LoadState<Workout> = .idle
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var actionError: String?

    var body: some View {
        LoadStateView(state: state, retry: load) { workout in
            List {
                Section {
                    LabeledContent("Data", value: DayString.label(workout.date))
                    if let category = appState.category(workout.categoryId) {
                        LabeledContent("Kategoria", value: "\(category.icon) \(category.name)")
                    }
                    if let minutes = workout.durationMin {
                        LabeledContent("Czas", value: "\(minutes) min")
                    }
                    if let rpe = workout.rpe {
                        LabeledContent("RPE sesji", value: rpe.short())
                    }
                }

                ForEach(workout.exercises) { exercise in
                    Section {
                        if exercise.isSession {
                            Text(SessionFormat.summary(exercise))
                        } else {
                        ForEach(Array(exercise.sets.enumerated()), id: \.offset) { index, set in
                            HStack(alignment: .firstTextBaseline) {
                                Text(verbatim: "\(index + 1).")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 26, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(SetFormat.summary(set))
                                    if !set.notes.isEmpty {
                                        Text(set.notes).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if set.isWarmup { Tag("Rozgrzewka", color: .orange) }
                            }
                        }
                        }
                        if !exercise.isSession, !exercise.notes.isEmpty {
                            Text(exercise.notes).font(.footnote).foregroundStyle(.secondary)
                        }
                    } header: {
                        NavigationLink {
                            ExerciseDetailView(exerciseId: exercise.exerciseId)
                        } label: {
                            HStack(spacing: 4) {
                                Text(comboTitle(exercise))
                                if let variant = exercise.variant, !variant.isEmpty {
                                    Text(verbatim: "· \(variant)")
                                }
                                Image(systemName: "chevron.right").font(.caption2)
                            }
                        }
                        .textCase(nil)
                    }
                }

                if !workout.notes.isEmpty {
                    Section("Notatki") { Text(workout.notes) }
                }
            }
            .refreshable { await load() }
            .navigationTitle(workout.title.isEmpty ? String(localized: "Trening") : workout.title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Edytuj", systemImage: "pencil") { editing = true }
                        Button("Usuń", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $editing) {
                WorkoutEditorView(workoutId: workout.id, draft: WorkoutDraft(workout)) { saved in
                    state = .loaded(saved)
                    Task { await onChange() }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .alert("Usunąć ten trening?", isPresented: $confirmDelete) {
            Button("Usuń", role: .destructive) { Task { await delete() } }
            Button("Anuluj", role: .cancel) {}
        } message: {
            Text("Tej operacji nie można cofnąć.")
        }
        .alert("Błąd", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
        .task {
            await exercises.loadIfNeeded()
            await appState.loadCategoriesIfNeeded()
            if state.isIdle { await load() }
        }
    }

    private func load() async {
        let person = appState.activePersonId
        if state.value == nil, let cached: Workout = DiskCache.read("workout-\(workoutId)", person: person) {
            state = .loaded(cached)
        } else if state.value == nil {
            state = .loading
        }
        do {
            state = .loaded(try await APIClient.shared.workout(workoutId, person: person))
        } catch {
            guard !Task.isCancelled else { return }
            if state.value == nil { state = .failed(error.localizedDescription) } else { actionError = error.localizedDescription }
        }
    }

    private func delete() async {
        do {
            try await APIClient.shared.deleteWorkout(workoutId, person: appState.activePersonId)
            await onChange()
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func comboTitle(_ exercise: WorkoutExercise) -> String {
        let ids = exercise.sequence.count > 1 ? exercise.sequence : [exercise.exerciseId]
        return ids.map { exercises.name($0) }.joined(separator: " → ")
    }
}
