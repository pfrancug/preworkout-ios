import SwiftUI

/// Tab: logged workouts, newest first, grouped by month.
struct WorkoutsView: View {
    @Environment(AppState.self) private var appState
    @Environment(ExerciseStore.self) private var exercises
    @Environment(LiveStore.self) private var live
    @State private var state: LoadState<[WorkoutSummary]> = .idle
    @State private var creating = false
    @State private var pendingDelete: WorkoutSummary?
    @State private var actionError: String?
    @State private var deleted = 0

    var body: some View {
        NavigationStack {
            LoadStateView(state: state, retry: load) { workouts in
                List {
                    if workouts.isEmpty {
                        Section {
                            ContentUnavailableView {
                                Label("Brak treningów", systemImage: "dumbbell")
                            } description: {
                                Text("Zacznij trening w zakładce Na żywo albo dodaj go ręcznie przyciskiem +.")
                            }
                        }
                    }
                    ForEach(months(workouts)) { group in
                        Section(group.id) {
                            ForEach(group.items) { workout in
                                NavigationLink {
                                    WorkoutDetailView(workoutId: workout.id, onChange: load)
                                } label: {
                                    WorkoutRow(workout: workout)
                                }
                                .swipeActions {
                                    Button("Usuń", systemImage: "trash", role: .destructive) {
                                        pendingDelete = workout
                                    }
                                }
                            }
                        }
                    }
                }
                .refreshable { await load() }
                .onReceive(NotificationCenter.default.publisher(for: .outboxFlushed)) { _ in Task { await load() } }
            }
            .navigationTitle("Treningi")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        ExercisesView(embedded: true)
                    } label: {
                        Label("Ćwiczenia", systemImage: "figure.strengthtraining.traditional")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Nowy trening", systemImage: "plus") { creating = true }
                }
            }
            .sheet(isPresented: $creating) {
                WorkoutEditorView(workoutId: nil, draft: WorkoutDraft()) { _ in
                    Task { await load() }
                }
            }
            .alert(
                "Usunąć ten trening?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                presenting: pendingDelete
            ) { workout in
                Button("Usuń", role: .destructive) { Task { await delete(workout) } }
                Button("Anuluj", role: .cancel) {}
            } message: { _ in
                Text("Tej operacji nie można cofnąć.")
            }
            .alert("Błąd", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(actionError ?? "")
            }
            .sensoryFeedback(.success, trigger: deleted)
            .onChange(of: live.savedCount) { Task { await load() } }
        }
        .task {
            if state.isIdle { await load() }
        }
    }

    private struct MonthGroup: Identifiable {
        /// Localized month label (also the section title)
        let id: String
        var items: [WorkoutSummary]
    }

    private func months(_ workouts: [WorkoutSummary]) -> [MonthGroup] {
        let sorted = workouts.sorted { $0.date > $1.date }
        var result: [MonthGroup] = []
        for workout in sorted {
            let month = DayString.month(workout.date)
            if result.last?.id == month {
                result[result.count - 1].items.append(workout)
            } else {
                result.append(MonthGroup(id: month, items: [workout]))
            }
        }
        return result
    }

    private func load() async {
        let person = appState.activePersonId
        if state.value == nil, let cached: [WorkoutSummary] = DiskCache.read("workouts", person: person) {
            state = .loaded(cached)
        } else if state.value == nil {
            state = .loading
        }
        do {
            let list = try await APIClient.shared.workouts(person: person)
            state = .loaded(list)
        } catch {
            guard !Task.isCancelled else { return }
            if state.value == nil {
                state = .failed(error.localizedDescription)
            } else {
                actionError = error.localizedDescription
            }
        }
    }

    private func delete(_ workout: WorkoutSummary) async {
        do {
            try await APIClient.shared.deleteWorkout(workout.id, person: appState.activePersonId)
            deleted += 1
            if case .loaded(let list) = state {
                state = .loaded(list.filter { $0.id != workout.id })
            }
        } catch {
            actionError = error.localizedDescription
        }
    }
}

struct WorkoutRow: View {
    let workout: WorkoutSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(workout.title.isEmpty ? (workout.planDayName ?? String(localized: "Trening")) : workout.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(DayString.short(workout.date))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !workout.exerciseNames.isEmpty {
                Text(workout.exerciseNames.joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 12) {
                if workout.exerciseCount > 0 {
                    Label("\(workout.exerciseCount) ćw.", systemImage: "figure.strengthtraining.traditional")
                }
                if workout.setCount > 0 {
                    Label("\(workout.setCount) serii", systemImage: "number")
                }
                if let minutes = workout.durationMin {
                    Label("\(minutes) min", systemImage: "clock")
                }
                if let rpe = workout.rpe {
                    Text(verbatim: "RPE \(rpe.short())")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
        }
        .padding(.vertical, 2)
    }
}
