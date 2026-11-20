import SwiftUI

/// Tab "Live": the running workout, or the start screen when nothing runs.
struct LiveTab: View {
    @Environment(LiveStore.self) private var live

    var body: some View {
        ZStack {
            if live.session != nil {
                LiveWorkoutView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                LiveStartView()
                    .transition(.opacity)
            }
        }
        .animation(LV.spring, value: live.session == nil)
        .toolbarBackground(LV.bg, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
    }
}

/// Start screen: one big orb to start right away, recent workouts to repeat.
private struct LiveStartView: View {
    @Environment(LiveStore.self) private var live
    @Environment(AppState.self) private var appState
    @Environment(ExerciseStore.self) private var library
    @State private var recent: [WorkoutSummary] = []
    @State private var loadingId: String?
    @State private var error: String?
    @State private var pulse = false

    var body: some View {
        ZStack {
            LiveAmbient(mood: .active)
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 40)
                    VStack(spacing: 8) {
                        Text("Trening na żywo").lvCaps()
                        Text(verbatim: DayString.dayLong(DayString.today))
                            .font(.system(size: 15))
                            .foregroundStyle(LV.muted)
                    }
                    ZStack {
                        Circle()
                            .stroke(LV.ember.opacity(0.25), lineWidth: 1.5)
                            .frame(width: 210, height: 210)
                            .scaleEffect(pulse ? 1.08 : 0.96)
                            .opacity(pulse ? 0.2 : 0.8)
                        Circle()
                            .stroke(LV.flame.opacity(0.18), lineWidth: 1)
                            .frame(width: 250, height: 250)
                            .scaleEffect(pulse ? 1.04 : 0.98)
                        LVOrb(mood: .active, size: 150, label: "Start") {
                            live.tap()
                            live.start()
                        } content: {
                            VStack(spacing: 2) {
                                Image(systemName: "play.fill").font(.system(size: 46)).offset(x: 4)
                                Text("Start").font(.system(size: 15, weight: .heavy)).textCase(.uppercase).tracking(1.5)
                            }
                        }
                    }
                    .frame(height: 290)
                    .padding(.top, 24)
                    Text("Ćwiczenia dodajesz w trakcie. Przerwy, stoper i serie liczą się same.")
                        .font(.system(size: 15))
                        .foregroundStyle(LV.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                        .padding(.top, 16)

                    if !recent.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Powtórz trening").lvCaps()
                            ForEach(recent) { w in
                                repeatRow(w)
                            }
                        }
                        .frame(maxWidth: 460)
                        .padding(.top, 40)
                    }
                    if let error {
                        Text(verbatim: error).font(.footnote).foregroundStyle(LV.danger).padding(.top, 12)
                    }
                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(LV.text)
        .preferredColorScheme(.dark)
        .task { await loadRecent() }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private func repeatRow(_ w: WorkoutSummary) -> some View {
        Button {
            Task { await repeatWorkout(w) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 40, height: 40)
                    .background(LV.ember.opacity(0.18), in: Circle())
                    .foregroundStyle(LV.ember)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: w.title.isEmpty ? w.exerciseNames.prefix(3).joined(separator: ", ") : w.title)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    Text(verbatim: "\(DayString.short(w.date)) · \(w.exerciseNames.prefix(4).joined(separator: ", "))")
                        .font(.system(size: 13))
                        .foregroundStyle(LV.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if loadingId == w.id {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right").foregroundStyle(LV.faint)
                }
            }
            .padding(12)
            .lvGlass(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(LVPress(scale: 0.97))
        .disabled(loadingId != nil)
    }

    private func loadRecent() async {
        guard let list = try? await APIClient.shared.workouts(person: appState.activePersonId) else { return }
        recent = Array(list.filter { $0.exerciseCount > 0 }.sorted { $0.date > $1.date }.prefix(3))
    }

    /// Same exercises, order, supersets and set count; the first working set
    /// of last time is the starting point for each exercise.
    private func repeatWorkout(_ summary: WorkoutSummary) async {
        loadingId = summary.id
        defer { loadingId = nil }
        do {
            let workout = try await APIClient.shared.workout(summary.id, person: appState.activePersonId)
            let exercises = workout.exercises.map { we -> LiveExercise in
                var item = we
                item.id = newId()
                var e = LiveExercise(item: item, defaultRest: live.defaultRest)
                e.plannedSets = max(1, we.sets.filter { !$0.isWarmup }.count)
                if var first = we.sets.first(where: { !$0.isWarmup }) ?? we.sets.first {
                    first.notes = ""
                    first.restSeconds = nil
                    first.isWarmup = false
                    e.pending = first
                }
                if let rest = we.sets.compactMap(\.restSeconds).first, rest > 0 { e.restSeconds = rest }
                return e
            }
            live.tap()
            live.start(exercises: exercises, title: workout.title)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
