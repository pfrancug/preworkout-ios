import SwiftUI

/// Full-screen live workout: clock, current exercise with quick set entry,
/// rest timer, the exercise queue (supersets / combos) and finishing.
struct LiveWorkoutView: View {
    @Environment(LiveStore.self) private var live
    @Environment(ExerciseStore.self) private var library

    @State private var picking = false
    @State private var picked: Exercise?
    @State private var addGroupId: String?
    @State private var showExtras = false
    @State private var editing: EditTarget?
    @State private var pendingRemove: Int?
    @State private var confirmDiscard = false
    @State private var confirmUnfinished = false
    @State private var finishing = false
    @State private var logged = 0

    private struct EditTarget: Identifiable {
        let index: Int
        let setIndex: Int
        var id: String { "\(index)-\(setIndex)" }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let session = live.session {
                    content(session)
                } else {
                    ProgressView()
                }
            }
            .toolbar { toolbar }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $finishing) {
                LiveFinishView()
            }
        }
        .task { await library.loadIfNeeded() }
        .sensoryFeedback(.success, trigger: logged)
        .sheet(isPresented: $picking) {
            ExercisePickerView { exercise in
                if addGroupId != nil || live.session?.currentExercise == nil {
                    add(exercise, mode: .end)
                } else {
                    picked = exercise
                }
            }
        }
        .confirmationDialog(
            "Dodaj ćwiczenie",
            isPresented: Binding(get: { picked != nil }, set: { if !$0 { picked = nil } }),
            titleVisibility: .visible,
            presenting: picked
        ) { exercise in
            Button("Na koniec") { add(exercise, mode: .end) }
            Button("Zaraz po bieżącym") { add(exercise, mode: .next) }
            Button("Superseria z bieżącym") { add(exercise, mode: .superset) }
            Button("Do bieżącej kombinacji (bez przerwy)") { add(exercise, mode: .combo) }
        } message: { exercise in
            Text(verbatim: exercise.name)
        }
        .confirmationDialog(
            "Usunąć z seriami?",
            isPresented: Binding(get: { pendingRemove != nil }, set: { if !$0 { pendingRemove = nil } }),
            titleVisibility: .visible,
            presenting: pendingRemove
        ) { index in
            Button("Usuń", role: .destructive) { live.update { s, _ in s.removeExercise(index) } }
        }
        .confirmationDialog("Porzucić ten trening?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Porzuć trening", role: .destructive) { live.clear() }
        } message: {
            Text("Wszystkie serie zapisane w tej sesji przepadną. Tego nie da się cofnąć.")
        }
        .confirmationDialog("Nie można jeszcze zakończyć", isPresented: $confirmUnfinished, titleVisibility: .visible) {
            Button("Pomiń niedokończone") {
                live.update { s, _ in s.skipIncomplete() }
                finishing = true
            }
            Button("Usuń niedokończone", role: .destructive) {
                live.update { s, _ in s.removeIncomplete() }
                finishing = true
            }
            Button("Wróć do treningu", role: .cancel) {}
        } message: {
            Text("Niedokończone ćwiczenia: \(live.session?.incomplete.count ?? 0)")
        }
        .sheet(item: $editing) { target in
            if let e = live.session?.exercises[safe: target.index], let set = e.item.sets[safe: target.setIndex] {
                LiveSetEditor(
                    title: live.name(of: e),
                    setNumber: target.setIndex + 1,
                    measurement: measurement(e),
                    set: set,
                    onSave: { value in live.update { s, _ in s.updateSet(target.index, target.setIndex, value) } },
                    onDelete: { live.update { s, _ in s.deleteSet(target.index, target.setIndex) } }
                )
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Zwiń (trening trwa dalej)", systemImage: "chevron.down") { live.presented = false }
        }
        ToolbarItem(placement: .principal) {
            if let session = live.session {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    VStack(spacing: 0) {
                        Text(verbatim: Clock.elapsed(session.elapsedMs(LiveSession.nowMs)))
                            .font(.headline.monospacedDigit())
                        if session.isPaused {
                            Text("Pauza").font(.caption2).foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if let session = live.session {
                Button {
                    live.tap()
                    live.update { s, now in
                        if session.isPaused { s.resume(now) } else { s.pause(now) }
                    }
                } label: {
                    if session.isPaused {
                        Label("Wznów", systemImage: "play.fill")
                    } else {
                        Label("Pauza", systemImage: "pause.fill")
                    }
                }
            }
            Menu {
                settingsMenu
                Divider()
                Button("Porzuć trening", systemImage: "trash", role: .destructive) { confirmDiscard = true }
            } label: {
                Label("Menu treningu", systemImage: "ellipsis.circle")
            }
        }
    }

    @ViewBuilder
    private var settingsMenu: some View {
        @Bindable var store = live
        Picker(selection: $store.defaultRest) {
            ForEach([30, 45, 60, 75, 90, 120, 150, 180, 240, 300], id: \.self) { seconds in
                Text(verbatim: Clock.text(Double(seconds))).tag(seconds)
            }
        } label: {
            Label("Domyślna przerwa", systemImage: "timer")
        }
        .pickerStyle(.menu)
        Toggle(isOn: $store.haptics) { Label("Wibracje", systemImage: "iphone.radiowaves.left.and.right") }
        Toggle(isOn: $store.sound) { Label("Dźwięk na koniec przerwy", systemImage: "speaker.wave.2") }
    }

    // MARK: Content

    private func content(_ session: LiveSession) -> some View {
        List {
            if session.isPaused {
                Section {
                    Label("Pauza: zegar treningu i przerwa są zatrzymane.", systemImage: "pause.circle")
                        .foregroundStyle(.orange)
                }
            }
            if let rest = session.rest {
                RestSection(rest: rest, session: session)
            }
            if session.exercises.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("Brak ćwiczeń", systemImage: "figure.strengthtraining.traditional")
                    } description: {
                        Text("Dodawaj ćwiczenia na bieżąco: wyszukiwarka wybacza literówki.")
                    } actions: {
                        Button("Dodaj ćwiczenie", systemImage: "plus") { openAdd() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            } else if let e = session.currentExercise {
                currentSection(session, e)
                if !e.item.sets.isEmpty { loggedSection(session, e) }
                queueSection(session)
            }
            Section {
                Button {
                    requestFinish(session)
                } label: {
                    Label("Zakończ trening", systemImage: "flag.checkered")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .listSectionSpacing(.compact)
    }

    private func measurement(_ e: LiveExercise) -> String {
        library.byId[e.countedExerciseId]?.measurement ?? "reps"
    }

    private func timerField(_ e: LiveExercise) -> LiveSession.TimerField? {
        switch measurement(e) {
        case "hold": return .hold
        case "distance_time": return .duration
        default: return e.pending.durationSeconds != nil ? .duration : nil
        }
    }

    @ViewBuilder
    private func currentSection(_ session: LiveSession, _ e: LiveExercise) -> some View {
        let index = session.current
        let done = e.item.sets.count
        let planned = max(e.plannedSets, done)
        let closed = e.status == .done || e.status == .skipped
        let n = index + 1
        let total = session.exercises.count
        let setNumber = min(done + 1, planned + (closed ? 0 : 1))
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if let g = e.item.groupId, let label = session.groupLabels[g] {
                        Tag("Superseria \(label)", color: .purple)
                    }
                    if e.item.sequence.count > 1 { Tag("Combo", color: .teal) }
                    Spacer()
                    Text("Ćwiczenie \(n) z \(total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(verbatim: live.name(of: e))
                    .font(.title2.bold())
                ProgressView(value: Double(min(done, planned)), total: Double(max(planned, 1)))
                    .tint(closed ? .green : .accentColor)
                HStack {
                    Text("Seria \(setNumber) z \(planned)")
                    if let last = e.item.sets.last {
                        Text(verbatim: "·")
                        Text("ostatnio \(LiveFormat.set(last))")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if let target = LiveFormat.target(e.target) {
                    Label { Text(verbatim: target) } icon: { Image(systemName: "scope") }
                        .font(.subheadline)
                }
            }
            .padding(.vertical, 4)

            if closed {
                if e.status == .done {
                    Label("Ćwiczenie ukończone", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Pominięte", systemImage: "forward.fill")
                        .foregroundStyle(.secondary)
                }
                Button("Wróć do niego", systemImage: "arrow.uturn.backward") {
                    live.update { s, _ in s.reopenExercise(index) }
                }
                if let next = session.nextOpenIndex(after: index) {
                    Button("Następne ćwiczenie", systemImage: "arrow.right") {
                        live.update { s, _ in s.goTo(next) }
                    }
                }
            } else {
                entryRows(session, e, index: index, done: done, planned: planned)
            }
        }
    }

    @ViewBuilder
    private func entryRows(_ session: LiveSession, _ e: LiveExercise, index: Int, done: Int, planned: Int) -> some View {
        let pending = Binding(
            get: { live.session?.exercises[safe: index]?.pending ?? WorkoutSet() },
            set: { value in live.update { s, _ in if s.exercises.indices.contains(index) { s.exercises[index].pending = value } } }
        )
        let field = timerField(e)
        if let field {
            SetTimerRow(session: session, exercise: e, field: field)
        }
        SetFieldsView(measurement: measurement(e), set: pending, showExtras: showExtras)
        Button {
            withAnimation { showExtras.toggle() }
        } label: {
            if showExtras {
                Label("Mniej", systemImage: "chevron.up")
            } else {
                Label("Ciężar, RPE, notatka", systemImage: "slider.horizontal.3")
            }
        }
        .font(.subheadline)

        Button {
            live.update { s, now in
                if let field, s.setTimer != nil { s.stopSetTimer(now, field: field) }
                s.logSet(now)
            }
            logged += 1
        } label: {
            Label("Zapisz serię \(done + 1)", systemImage: "checkmark")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)

        HStack {
            if let last = e.item.sets.last {
                Button("Kopiuj poprzednią", systemImage: "doc.on.doc") {
                    live.tap()
                    var copy = last
                    copy.restSeconds = nil
                    copy.notes = ""
                    pending.wrappedValue = copy
                }
            }
            Spacer()
            if done > 0 && done >= e.plannedSets {
                Button("Jeszcze seria", systemImage: "plus") {
                    live.update { s, _ in s.exercises[index].plannedSets = max(s.exercises[index].plannedSets, done) + 1 }
                }
            }
        }
        .buttonStyle(.borderless)
        .font(.subheadline)

        HStack {
            if done > 0 {
                Button("Zakończ ćwiczenie", systemImage: "checkmark.circle") {
                    live.tap()
                    live.update { s, now in s.finishExercise(index, now) }
                }
            } else {
                Button("Pomiń", systemImage: "forward") {
                    live.tap()
                    live.update { s, _ in s.skipExercise(index) }
                }
            }
            Spacer()
            RestSettingControl(index: index, seconds: e.restSeconds)
        }
        .buttonStyle(.borderless)
        .font(.subheadline)
    }

    private func loggedSection(_ session: LiveSession, _ e: LiveExercise) -> some View {
        let index = session.current
        return Section("Zapisane serie") {
            ForEach(Array(e.item.sets.enumerated()), id: \.offset) { setIndex, set in
                Button {
                    editing = EditTarget(index: index, setIndex: setIndex)
                } label: {
                    HStack {
                        Text("Seria \(setIndex + 1)")
                            .foregroundStyle(.secondary)
                        if set.isWarmup { Tag("Rozgrzewka", color: .orange) }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(verbatim: LiveFormat.set(set))
                            if let rest = set.restSeconds {
                                Text("przerwa \(Clock.text(Double(rest)))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .tint(.primary)
                .swipeActions {
                    Button("Usuń", systemImage: "trash", role: .destructive) {
                        live.update { s, _ in s.deleteSet(index, setIndex) }
                    }
                }
            }
        }
    }

    private func queueSection(_ session: LiveSession) -> some View {
        let labels = session.groupLabels
        return Section {
            ForEach(Array(session.exercises.enumerated()), id: \.element.id) { index, e in
                QueueRow(
                    exercise: e,
                    name: live.name(of: e),
                    groupLabel: e.item.groupId.flatMap { labels[$0] },
                    isCurrent: index == session.current
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    live.tap()
                    live.update { s, _ in s.goTo(index) }
                }
                .swipeActions(edge: .trailing) {
                    Button("Usuń", systemImage: "trash") { pendingRemove = index }
                        .tint(.red)
                    if e.isOpen {
                        Button("Pomiń", systemImage: "forward") { live.update { s, _ in s.skipExercise(index) } }
                    } else {
                        Button("Wróć do niego", systemImage: "arrow.uturn.backward") { live.update { s, _ in s.reopenExercise(index) } }
                    }
                }
                .contextMenu {
                    Button("Wyżej", systemImage: "arrow.up") { live.update { s, _ in s.moveExercise(index, by: -1) } }
                        .disabled(index == 0)
                    Button("Niżej", systemImage: "arrow.down") { live.update { s, _ in s.moveExercise(index, by: 1) } }
                        .disabled(index == session.exercises.count - 1)
                    if let g = e.item.groupId {
                        Button("Dodaj do superserii", systemImage: "plus.rectangle.on.rectangle") { openAdd(group: g) }
                        Button("Wyłącz z superserii", systemImage: "rectangle.badge.minus") { live.update { s, _ in s.ungroup(index) } }
                    }
                    if e.item.sequence.count > 1 {
                        Button("Rozdziel combo", systemImage: "scissors") { live.update { s, _ in s.splitCombo(index) } }
                    }
                    Button("Usuń", systemImage: "trash", role: .destructive) { pendingRemove = index }
                }
            }
            Button("Dodaj ćwiczenie", systemImage: "plus") { openAdd() }
        } header: {
            Text("Trening")
        } footer: {
            Text("Dotknij, aby przejść. Przytrzymaj, aby zmienić kolejność lub superserię.")
        }
    }

    // MARK: Actions

    private func openAdd(group: String? = nil) {
        addGroupId = group
        picking = true
    }

    private func add(_ exercise: Exercise, mode: AddMode) {
        let group = addGroupId
        live.tap()
        live.update { s, _ in
            if let group, let first = s.groupIndices(group).first {
                // Add into an existing superset: make it current, then superset mode.
                let previous = s.current
                s.current = first
                s.addExercise(exercise.id, mode: .superset, defaultRest: live.defaultRest)
                s.current = min(previous, s.exercises.count - 1)
            } else {
                s.addExercise(exercise.id, mode: mode, defaultRest: live.defaultRest)
            }
        }
        addGroupId = nil
        picked = nil
    }

    private func requestFinish(_ session: LiveSession) {
        if session.incomplete.isEmpty {
            finishing = true
        } else {
            confirmUnfinished = true
        }
    }
}

/// Rest countdown with −15 s / +15 s / skip.
private struct RestSection: View {
    let rest: LiveRest
    let session: LiveSession
    @Environment(LiveStore.self) private var live

    var body: some View {
        Section {
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let left = rest.remaining(LiveSession.nowMs)
                let over = left <= 0
                VStack(spacing: 10) {
                    Group {
                        if over {
                            Text("Czas start")
                        } else if rest.pausedRemaining != nil {
                            Text("Przerwa (pauza)")
                        } else {
                            Text("Przerwa")
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(over ? .green : .secondary)
                    Text(verbatim: Clock.text(left))
                        .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(over ? .green : .primary)
                        .contentTransition(.numericText(countsDown: true))
                    ProgressView(value: max(0, min(1, 1 - left / max(rest.durationSec, 1))))
                        .tint(over ? .green : .accentColor)
                    HStack(spacing: 12) {
                        Button {
                            live.tap()
                            live.update { s, now in s.adjustRest(by: -LiveSession.restStep, now) }
                        } label: {
                            Text(verbatim: "−15 s").frame(maxWidth: .infinity)
                        }
                        .accessibilityLabel(Text("Przerwa krótsza o 15 sekund"))
                        Button {
                            live.tap()
                            live.update { s, now in s.adjustRest(by: LiveSession.restStep, now) }
                        } label: {
                            Text(verbatim: "+15 s").frame(maxWidth: .infinity)
                        }
                        .accessibilityLabel(Text("Przerwa dłuższa o 15 sekund"))
                        Button {
                            live.tap()
                            live.update { s, now in s.closeRest(now) }
                        } label: {
                            Text("Pomiń przerwę").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
        } footer: {
            if let e = session.exercises.first(where: { $0.item.id == rest.itemId }), let set = e.item.sets[safe: rest.setIndex] {
                Text("Seria \(rest.setIndex + 1) · \(LiveFormat.set(set))")
            }
        }
    }
}

/// Stopwatch for hold / timed sets; Stop puts the time into the set.
private struct SetTimerRow: View {
    let session: LiveSession
    let exercise: LiveExercise
    let field: LiveSession.TimerField
    @Environment(LiveStore.self) private var live

    var body: some View {
        HStack {
            if let timer = session.setTimer {
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    let seconds = timer.elapsed(LiveSession.nowMs)
                    let reached = timer.targetSec.map { seconds >= $0 } ?? false
                    VStack(alignment: .leading, spacing: 2) {
                        Group {
                            if field == .hold { Text("Trzymasz") } else { Text("Trwa") }
                        }
                        .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(verbatim: Clock.text(seconds.rounded(.down)))
                            .font(.title.monospacedDigit().bold())
                            .foregroundStyle(reached ? .green : .primary)
                    }
                }
                Spacer()
                Button("Stop", systemImage: "stop.fill") {
                    live.success()
                    live.update { s, now in s.stopSetTimer(now, field: field) }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stoper serii")
                    if let target = targetSeconds {
                        Text("Cel \(target.short(0)) s")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Start", systemImage: "play.fill") {
                    live.tap()
                    live.update { s, now in s.startSetTimer(now, target: targetSeconds) }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var targetSeconds: Double? {
        field == .hold ? (exercise.pending.holdSeconds ?? exercise.target?["targetHoldMax"] ?? exercise.target?["targetHoldMin"]) : nil
    }
}

/// Rest between sets of this exercise (−15 / +15 s).
private struct RestSettingControl: View {
    let index: Int
    let seconds: Int
    @Environment(LiveStore.self) private var live

    var body: some View {
        HStack(spacing: 6) {
            Button {
                live.update { s, _ in s.exercises[index].restSeconds = max(0, seconds - LiveSession.restStep) }
            } label: {
                Image(systemName: "minus.circle")
            }
            .accessibilityLabel(Text("Krótsza przerwa w tym ćwiczeniu"))
            .disabled(seconds <= 0)
            Label { Text(verbatim: Clock.text(Double(seconds))).monospacedDigit() } icon: { Image(systemName: "timer") }
            Button {
                live.update { s, _ in s.exercises[index].restSeconds = min(900, seconds + LiveSession.restStep) }
            } label: {
                Image(systemName: "plus.circle")
            }
            .accessibilityLabel(Text("Dłuższa przerwa w tym ćwiczeniu"))
        }
        .accessibilityElement(children: .contain)
    }
}

private struct QueueRow: View {
    let exercise: LiveExercise
    let name: String
    let groupLabel: String?
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let groupLabel { Tag("Superseria \(groupLabel)", color: .purple) }
                    Text(verbatim: name)
                        .fontWeight(isCurrent ? .semibold : .regular)
                        .foregroundStyle(exercise.status == .skipped ? .secondary : .primary)
                        .lineLimit(2)
                }
                Text(verbatim: "\(exercise.item.sets.count) / \(max(exercise.plannedSets, exercise.item.sets.count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            if isCurrent {
                Image(systemName: "chevron.left").font(.caption).foregroundStyle(.tint)
            }
        }
    }

    private var icon: String {
        switch exercise.status {
        case .done: return "checkmark.circle.fill"
        case .skipped: return "forward.circle"
        case .active: return "play.circle.fill"
        case .pending: return isCurrent ? "play.circle" : "circle"
        }
    }

    private var color: Color {
        switch exercise.status {
        case .done: return .green
        case .skipped: return .secondary
        default: return isCurrent ? .accentColor : .secondary
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
