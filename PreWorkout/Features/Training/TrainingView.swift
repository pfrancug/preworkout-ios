import SwiftUI

struct TrainingView: View {
    private enum Mode: Hashable { case workouts, plans }
    @State private var mode: Mode = .workouts

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .workouts: WorkoutListView()
                case .plans: PlanListView()
                }
            }
            .safeAreaInset(edge: .top) {
                Picker("Widok", selection: $mode) {
                    Text("Treningi").tag(Mode.workouts)
                    Text("Plany").tag(Mode.plans)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .background(.bar)
            }
            .navigationTitle("Trening")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        LiveWorkoutView()
                    } label: {
                        Label("Prowadź trening", systemImage: "timer")
                    }
                }
            }
        }
    }
}

// MARK: Workouts

struct WorkoutListView: View {
    @Environment(AppState.self) private var appState
    @State private var state: LoadState<[WorkoutSummary]> = .idle

    var body: some View {
        LoadStateView(state: state, retry: load) { workouts in
            if workouts.isEmpty {
                ContentUnavailableView("Brak treningów", systemImage: "dumbbell")
            } else {
                List(workouts) { workout in
                    NavigationLink {
                        WorkoutDetailView(summary: workout)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(workout.title.isEmpty ? (workout.planDayName ?? String(localized: "Trening")) : workout.title)
                                    .font(.headline)
                                Spacer()
                                Text(DayString.label(workout.date)).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(workout.exerciseNames.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            Text("\(workout.exerciseCount) ćw. · \(workout.setCount) serii")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        if case .loaded = state {} else { state = .loading }
        do {
            let list = try await APIClient.shared.workouts(person: appState.activePersonId)
            state = .loaded(list.sorted { $0.date > $1.date })
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

struct WorkoutDetailView: View {
    @Environment(AppState.self) private var appState
    let summary: WorkoutSummary
    @State private var state: LoadState<Workout> = .idle

    /// Names come with the list summary (same order as the ids).
    private var names: [String: String] {
        Dictionary(zip(summary.exerciseIds, summary.exerciseNames), uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        LoadStateView(state: state, retry: load) { workout in
            List {
                Section {
                    LabeledContent("Data", value: DayString.label(workout.date))
                    if let minutes = workout.durationMin { LabeledContent("Czas", value: "\(minutes) min") }
                    if let rpe = workout.rpe { LabeledContent("RPE", value: Optional(rpe).display(1)) }
                    if !workout.notes.isEmpty { Text(workout.notes).font(.callout) }
                }
                ForEach(workout.exercises) { exercise in
                    Section(names[exercise.exerciseId] ?? exercise.exerciseId) {
                        ForEach(Array(exercise.sets.enumerated()), id: \.offset) { index, workoutSet in
                            HStack {
                                Text(workoutSet.isWarmup ? "W" : "\(index + 1)")
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    .frame(width: 24, alignment: .leading)
                                Text(SetFormatter.text(workoutSet))
                                Spacer()
                                if !workoutSet.notes.isEmpty {
                                    Text(workoutSet.notes).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                        if !exercise.notes.isEmpty {
                            Text(exercise.notes).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(summary.title.isEmpty ? String(localized: "Trening") : summary.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await APIClient.shared.workout(summary.id, person: appState.activePersonId))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

enum SetFormatter {
    static func text(_ set: WorkoutSet) -> String {
        var parts: [String] = []
        if let reps = set.reps { parts.append("\(reps)×") }
        if let hold = set.holdSeconds { parts.append(Optional(hold).display(0, unit: "s")) }
        if let duration = set.durationSeconds { parts.append("\(duration) s") }
        if let distance = set.distanceM { parts.append(Optional(distance).display(0, unit: "m")) }
        if let kg = set.weightKg, kg > 0 { parts.append("+" + Optional(kg).display(1, unit: "kg")) }
        if set.assistance != "none" { parts.append(set.assistance) }
        if let rpe = set.rpe { parts.append("RPE " + Optional(rpe).display(1)) }
        if let rir = set.rir { parts.append("RIR \(rir)") }
        return parts.isEmpty ? "–" : parts.joined(separator: " ")
    }
}

// MARK: Plans

struct PlanListView: View {
    @Environment(AppState.self) private var appState
    @State private var state: LoadState<[TrainingPlanSummary]> = .idle

    var body: some View {
        LoadStateView(state: state, retry: load) { plans in
            if plans.isEmpty {
                ContentUnavailableView("Brak planów", systemImage: "list.clipboard")
            } else {
                List(plans) { plan in
                    NavigationLink {
                        PlanDetailView(planId: plan.id, title: plan.name)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(plan.name).font(.headline)
                                if plan.isActive {
                                    Text("Aktywny").font(.caption2.bold())
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(.green.opacity(0.2), in: Capsule())
                                }
                            }
                            if !plan.goal.isEmpty {
                                Text(plan.goal).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Text("\(plan.dayCount) dni").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        if case .loaded = state {} else { state = .loading }
        do {
            let plans = try await APIClient.shared.plans(person: appState.activePersonId)
            state = .loaded(plans.sorted { ($0.isActive ? 0 : 1, $1.updatedAt) < ($1.isActive ? 0 : 1, $0.updatedAt) })
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

struct PlanDetailView: View {
    @Environment(AppState.self) private var appState
    let planId: String
    let title: String
    @State private var state: LoadState<TrainingPlan> = .idle
    @State private var names: [String: String] = [:]

    var body: some View {
        LoadStateView(state: state, retry: load) { plan in
            List {
                if !plan.goal.isEmpty || !plan.notes.isEmpty {
                    Section {
                        if !plan.goal.isEmpty { LabeledContent("Cel", value: plan.goal) }
                        if !plan.notes.isEmpty { Text(plan.notes).font(.callout) }
                    }
                }
                ForEach(plan.days) { day in
                    Section(day.week.map { String(localized: "Tydzień \($0): \(day.name)") } ?? day.name) {
                        ForEach(day.exercises) { exercise in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(names[exercise.exerciseId] ?? exercise.exerciseId)
                                Text(PlanTargetFormatter.text(exercise))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        state = .loading
        do {
            let plan = try await APIClient.shared.plan(planId, person: appState.activePersonId)
            state = .loaded(plan)
            names = await ExerciseNames.shared.names(for: plan.days.flatMap { $0.exercises.map(\.exerciseId) })
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

enum PlanTargetFormatter {
    static func text(_ e: PlanExercise) -> String {
        var parts: [String] = []
        let sets = e.targetSets.map { "\($0)×" } ?? ""
        if let min = e.targetRepsMin {
            let max = e.targetRepsMax.flatMap { $0 != min ? "–\($0)" : nil } ?? ""
            parts.append("\(sets)\(min)\(max)")
        } else if let hold = e.targetHoldMin {
            parts.append(sets + Optional(hold).display(0, unit: "s"))
        } else if !sets.isEmpty {
            parts.append(String(sets.dropLast()) + " serie")
        }
        if let kg = e.targetWeightKg, kg > 0 { parts.append("+" + Optional(kg).display(1, unit: "kg")) }
        if let rest = e.restSeconds { parts.append("przerwa \(rest) s") }
        if let variant = e.variant, !variant.isEmpty { parts.append(variant) }
        return parts.joined(separator: " · ")
    }
}

/// Small in-memory cache of exercise names (the library is shared by all people).
actor ExerciseNames {
    static let shared = ExerciseNames()
    private var cache: [String: String] = [:]

    func names(for ids: [String]) async -> [String: String] {
        let missing = Set(ids).subtracting(cache.keys)
        await withTaskGroup(of: (String, String?).self) { group in
            for id in missing {
                group.addTask { (id, try? await APIClient.shared.exercise(id).name) }
            }
            for await (id, name) in group {
                if let name { cache[id] = name }
            }
        }
        return cache
    }
}
