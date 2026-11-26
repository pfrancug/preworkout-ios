import SwiftUI

/// Summary after "Finish workout": time, sets, volume, best sets; title, RPE
/// and notes; saves the session as a normal workout (`POST /workouts`).
struct LiveFinishView: View {
    @Environment(LiveStore.self) private var live
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    /// Set once the server has the workout: the screen is on its way out.
    @State private var done = false
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
                VStack(spacing: 6) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 40, weight: .heavy))
                        .foregroundStyle(.black)
                        .frame(width: 96, height: 96)
                        .background(LiveMood.done.cta, in: Circle())
                        .shadow(color: LV.lime.opacity(0.6), radius: 36)
                        .padding(.top, 36)
                        .padding(.bottom, 12)
                    Text("Świetna robota")
                        .font(.system(size: 30, weight: .heavy))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7)
                        .lineLimit(2)
                    Text(verbatim: DayString.dayLong(session.date))
                        .foregroundStyle(LV.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
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
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            if !stats.highlights.isEmpty {
                Section("Najlepsze w tym treningu") {
                    ForEach(stats.highlights) { h in
                        HStack {
                            Image(systemName: h.icon).foregroundStyle(LV.gold).frame(width: 24)
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
                TextField("Dodaj tytuł", text: binding(\.title, ""))
                    .maxLength(binding(\.title, ""), 120)
                Picker(selection: binding(\.rpe, nil)) {
                    Text(verbatim: "–").tag(Double?.none)
                    ForEach(Array(stride(from: 1.0, through: 10.0, by: 0.5)), id: \.self) { value in
                        Text(verbatim: value.short()).tag(Double?.some(value))
                    }
                } label: {
                    Text("Jak ciężko było?")
                }
                TextField("Notatki (opcjonalnie)", text: binding(\.notes, ""), axis: .vertical)
                    .maxLength(binding(\.notes, ""), 4000)
                    .lineLimit(2...6)
            } footer: {
                Text("RPE treningu: 1 bardzo lekko, 10 maksymalny wysiłek.")
            }

            if let error {
                Section { ErrorText(message: error) }
            }

            Section {
                LVCta(mood: .done) {
                    Task { await save() }
                } content: {
                    if saving {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "checkmark")
                        Text("Zapisz trening")
                    }
                }
                .disabled(saving || done)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .scrollClipDisabled()
        .background { LiveAmbient(mood: .done) }
        .safeAreaInset(edge: .top, spacing: 0) {
            keepTrainingBar
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.visible, for: .tabBar)
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
        .keepsTabBarVisible("liveFinish")
    }

    /// Leading action in the safe area, not the system toolbar: the live
    /// workout hides the nav bar, and showing it only on this screen left
    /// "Keep training" misaligned under the status bar.
    private var keepTrainingBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                dismiss()
            } label: {
                Text("Trenuj dalej")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(LV.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)
            .disabled(saving || done)
            .opacity(saving || done ? 0.45 : 1)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Never force-unwraps: text fields and pickers can still read or write
    /// their binding while the screen is being torn down after the session ended.
    private func binding<T>(_ path: WritableKeyPath<LiveSession, T>, _ fallback: T) -> Binding<T> {
        Binding(
            get: { live.session?[keyPath: path] ?? fallback },
            set: { value in
                guard live.session != nil, !done else { return }
                live.update { s, _ in s[keyPath: path] = value }
            }
        )
    }

    private func save() async {
        guard let session = live.session, !saving, !done else { return }
        // Close the keyboard first so no text field writes back during teardown.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        saving = true
        error = nil
        defer { saving = false }
        do {
            let now = LiveSession.nowMs
            let input = session.workoutInput(now)
            _ = try await APIClient.shared.createWorkout(input, person: appState.activePersonId)
            Analytics.send("Workout.liveFinished", [
                "exerciseCount": Analytics.exerciseCountBucket(input.exercises.count),
                "duration": Analytics.durationBucket(seconds: session.elapsedMs(now) / 1000),
                "hasSessionType": session.exercises.contains { $0.item.isSession } ? "true" : "false",
            ])
            done = true
            live.success()
            live.didSave(sessionId: session.id)
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
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .monospacedDigit()
            label
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .padding(4)
        .lvGlass(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
