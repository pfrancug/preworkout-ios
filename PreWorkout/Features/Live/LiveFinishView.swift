import SwiftUI

/// Summary after "Finish workout": time, sets, volume, best sets; title, RPE
/// and notes; saves the session as a normal workout (`POST /workouts`).
struct LiveFinishView: View {
    @Environment(LiveStore.self) private var live
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        if let session = live.session {
            form(session)
        } else {
            ProgressView()
        }
    }

    private func form(_ session: LiveSession) -> some View {
        let stats = Stats(session)
        return Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    if stats.sets > 0 {
                        Text("Świetna robota").font(.title.bold())
                    } else {
                        Text("Jeszcze nic nie zapisano").font(.title.bold())
                    }
                    Text(verbatim: DayString.dayLong(session.date))
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section {
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        StatTile(value: Clock.elapsed(session.elapsedMs(LiveSession.nowMs))) { Text("Czas") }
                        StatTile(value: "\(stats.exercises)") { Text("Ćwiczenia") }
                    }
                    GridRow {
                        StatTile(value: "\(stats.sets)") { Text("Serie") }
                        if stats.volume > 0 {
                            StatTile(value: stats.volume.short(0)) { Text("Objętość kg") }
                        } else {
                            StatTile(value: "\(stats.reps)") { Text("Powtórzenia") }
                        }
                    }
                    if stats.hold > 0 {
                        GridRow {
                            StatTile(value: Clock.text(stats.hold)) { Text("Czas utrzymań") }
                                .gridCellColumns(2)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            if !stats.highlights.isEmpty {
                Section("Najlepsze w tym treningu") {
                    ForEach(stats.highlights) { h in
                        HStack {
                            Image(systemName: h.icon).foregroundStyle(.tint).frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(h.label).font(.caption).foregroundStyle(.secondary)
                                Text(verbatim: live.name(of: h.exercise))
                            }
                            Spacer()
                            Text(verbatim: h.value).font(.headline).monospacedDigit()
                        }
                    }
                }
            }

            Section {
                TextField("Dodaj tytuł", text: binding(\.title))
                Picker(selection: binding(\.rpe)) {
                    Text(verbatim: "–").tag(Double?.none)
                    ForEach(Array(stride(from: 1.0, through: 10.0, by: 0.5)), id: \.self) { value in
                        Text(verbatim: value.short()).tag(Double?.some(value))
                    }
                } label: {
                    Text("Jak ciężko było?")
                }
                TextField("Notatki (opcjonalnie)", text: binding(\.notes), axis: .vertical)
                    .lineLimit(2...6)
            } footer: {
                Text("RPE treningu: 1 bardzo lekko, 10 maksymalny wysiłek.")
            }

            if let error {
                Section { ErrorText(message: error) }
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Spacer()
                        if saving { ProgressView() } else { Text("Zapisz trening").font(.headline) }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(saving || stats.sets == 0)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } footer: {
                if stats.sets == 0 {
                    Text("Brak zapisanych serii — nie ma czego zapisać.")
                }
            }
        }
        .navigationTitle("Zakończ trening")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Trenuj dalej") { dismiss() }
                    .disabled(saving)
            }
        }
    }

    private func binding<T>(_ path: WritableKeyPath<LiveSession, T>) -> Binding<T> {
        Binding(
            get: { live.session![keyPath: path] },
            set: { value in live.update { s, _ in s[keyPath: path] = value } }
        )
    }

    private func save() async {
        guard let session = live.session else { return }
        saving = true
        error = nil
        defer { saving = false }
        do {
            _ = try await APIClient.shared.createWorkout(session.workoutInput(LiveSession.nowMs), person: appState.activePersonId)
            live.success()
            live.didSave()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct StatTile<Caption: View>: View {
    let value: String
    @ViewBuilder let label: Caption

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: value)
                .font(.title2.bold())
                .monospacedDigit()
            label
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Same numbers as the web finish screen (warm-up sets excluded).
private struct Stats {
    struct Highlight: Identifiable {
        let id: String
        let icon: String
        let label: LocalizedStringKey
        let value: String
        let exercise: LiveExercise
    }

    let exercises: Int
    let sets: Int
    let volume: Double
    let reps: Int
    let hold: Double
    let highlights: [Highlight]

    init(_ session: LiveSession) {
        let done = session.exercises.filter { !$0.item.sets.isEmpty }
        let all = done.flatMap { e in e.item.sets.map { (e: e, set: $0) } }
        let work = all.filter { !$0.set.isWarmup }
        exercises = done.count
        sets = all.count
        volume = work.reduce(0) { $0 + Double($1.set.reps ?? 0) * ($1.set.weightKg ?? 0) }
        reps = work.reduce(0) { $0 + ($1.set.reps ?? 0) }
        hold = work.reduce(0) { $0 + ($1.set.holdSeconds ?? 0) }

        func best(_ score: (WorkoutSet) -> Double) -> (e: LiveExercise, set: WorkoutSet)? {
            var top: (e: LiveExercise, set: WorkoutSet)?
            for x in work where score(x.set) > 0 {
                if let t = top, score(x.set) <= score(t.set) { continue }
                top = x
            }
            return top
        }
        var list: [Highlight] = []
        let heaviest = best { $0.weightKg ?? 0 }
        if let h = heaviest {
            list.append(.init(id: "heavy", icon: "scalemass", label: "Najcięższa seria", value: LiveFormat.set(h.set), exercise: h.e))
        }
        if let r = best({ Double($0.reps ?? 0) }), r.set != heaviest?.set || r.e.id != heaviest?.e.id {
            list.append(.init(id: "reps", icon: "repeat", label: "Najwięcej powtórzeń", value: LiveFormat.set(r.set), exercise: r.e))
        }
        if let l = best({ $0.holdSeconds ?? 0 }) {
            list.append(.init(id: "hold", icon: "timer", label: "Najdłuższe utrzymanie", value: Clock.text(l.set.holdSeconds ?? 0), exercise: l.e))
        }
        highlights = list
    }
}
