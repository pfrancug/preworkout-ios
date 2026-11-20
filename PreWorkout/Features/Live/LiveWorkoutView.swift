import SwiftUI

/// The live workout, built like the web one: dark stage, the clock on top,
/// one big focal element in the middle (rest ring, set stopwatch or the reps
/// to do), and one big orb as the only primary action. What is DONE (lime
/// checks) and what is NOW (glowing "Now: set N") are never on the same chip.
struct LiveWorkoutView: View {
    @Environment(LiveStore.self) private var live
    @Environment(ExerciseStore.self) private var library

    @State private var sheet: SheetKind?
    @State private var picking = false
    @State private var picked: Exercise?
    @State private var addGroupId: String?
    @State private var confirmDiscard = false
    @State private var confirmUnfinished = false
    @State private var finishing = false
    @State private var logged = 0
    @State private var forward = true
    /// Exercise + set the stopwatch was just stopped for (orb turns into "done").
    @State private var timedKey: String?
    @State private var timedStep: (index: Int, field: SetField)?

    enum SheetKind: Identifiable {
        case log(LiveLogSheet.Mode, index: Int, setIndex: Int)
        case queue

        var id: String {
            switch self {
            case let .log(mode, index, setIndex): return "log-\(mode)-\(index)-\(setIndex)"
            case .queue: return "queue"
            }
        }
    }

    private enum Stage: String { case empty, active, rest, complete }

    var body: some View {
        NavigationStack {
            ZStack {
                if let session = live.session {
                    TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                        screen(session, now: ctx.date.timeIntervalSince1970 * 1000)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $finishing) { LiveFinishView() }
        }
        .preferredColorScheme(.dark)
        .task {
            await library.loadIfNeeded()
            ensureSteps()
        }
        .onChange(of: live.session?.exercises.map(\.item.sequence) ?? []) { _, _ in
            ensureSteps()
        }
        .sensoryFeedback(.success, trigger: logged)
        .sheet(item: $sheet) { kind in
            switch kind {
            case let .log(mode, index, setIndex): logSheet(mode, index: index, setIndex: setIndex)
            case .queue: LiveQueueSheet(onAdd: { group in openAdd(group: group) }, onFinish: requestFinish)
            }
        }
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
    }

    // MARK: Layout

    private func stage(_ session: LiveSession) -> Stage {
        guard let e = session.currentExercise else { return .empty }
        if session.rest != nil { return .rest }
        let closed = e.status == .done || e.status == .skipped
        if closed || (e.plannedSets > 0 && e.item.sets.count >= e.plannedSets) { return .complete }
        return .active
    }

    private func mood(_ session: LiveSession, _ stage: Stage) -> LiveMood {
        if session.isPaused { return .paused }
        switch stage {
        case .rest: return .rest
        case .complete: return .done
        default: return .active
        }
    }

    private func screen(_ session: LiveSession, now: Double) -> some View {
        let st = stage(session)
        let md = mood(session, st)
        let key = "\(st.rawValue)-\(session.currentExercise?.id ?? "")-\(session.rest?.startedAt ?? 0)"
        return ZStack {
            LiveAmbient(mood: md)
            VStack(spacing: 0) {
                header(session, now: now, mood: md)
                Group {
                    switch st {
                    case .empty: emptyStage
                    case .active: activeStage(session, now: now, mood: md)
                    case .rest: restStage(session, now: now)
                    case .complete: completeStage(session)
                    }
                }
                .frame(maxWidth: 460, maxHeight: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .id(key)
                .transition(.asymmetric(
                    insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                    removal: .opacity
                ))
                .contentShape(Rectangle())
                .gesture(browseGesture(session))
                dock(session, stage: st, now: now, mood: md)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
            .animation(LV.spring, value: key)
            if session.isPaused { pausedOverlay(session, now: now) }
        }
        .foregroundStyle(LV.text)
    }

    /// Horizontal swipe on the stage browses exercises.
    private func browseGesture(_ session: LiveSession) -> some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { g in
                guard abs(g.translation.width) > 80, abs(g.translation.width) > abs(g.translation.height) * 1.5 else { return }
                let target = session.current + (g.translation.width < 0 ? 1 : -1)
                guard session.exercises.indices.contains(target) else { return }
                forward = g.translation.width < 0
                live.tap()
                live.update { s, _ in s.goTo(target) }
            }
    }

    // MARK: Header: add · clock (tap = pause) · menu, then exercise progress

    private func header(_ session: LiveSession, now: Double, mood: LiveMood) -> some View {
        VStack(spacing: 12) {
            HStack {
                LVIconButton(icon: "plus", label: "Dodaj ćwiczenie") { openAdd() }
                Spacer()
                Button {
                    live.tap()
                    live.update { s, t in if s.isPaused { s.resume(t) } else { s.pause(t) } }
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(session.isPaused ? LV.gold : LV.danger)
                            .frame(width: 8, height: 8)
                            .shadow(color: session.isPaused ? .clear : LV.danger, radius: 4)
                            .opacity(session.isPaused || Int(now / 1000) % 2 == 0 ? 1 : 0.35)
                        Text(verbatim: Clock.elapsed(session.elapsedMs(now)))
                            .font(.system(size: 19, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 12))
                            .opacity(session.isPaused ? 1 : 0.6)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .lvGlass(Capsule())
                }
                .buttonStyle(LVPress(scale: 0.95))
                .accessibilityLabel(session.isPaused ? Text("Wznów") : Text("Pauza"))
                Spacer()
                menu(session)
            }
            if !session.exercises.isEmpty {
                LVSegments(session: session, mood: mood)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private func menu(_ session: LiveSession) -> some View {
        @Bindable var store = live
        return Menu {
            Button("Zakończ trening", systemImage: "flag.checkered") { requestFinish() }
            Button("Lista ćwiczeń", systemImage: "list.number") { sheet = .queue }
            if let e = session.currentExercise {
                let index = session.current
                Picker(selection: Binding(
                    get: { e.restSeconds },
                    set: { v in live.update { s, _ in if s.exercises.indices.contains(index) { s.exercises[index].restSeconds = v } } }
                )) {
                    ForEach(Self.restChoices(including: e.restSeconds), id: \.self) { sec in
                        Text(verbatim: Clock.text(Double(sec))).tag(sec)
                    }
                } label: {
                    Label("Przerwa w tym ćwiczeniu", systemImage: "timer")
                }
                .pickerStyle(.menu)
            }
            Divider()
            Picker(selection: $store.defaultRest) {
                ForEach([30, 45, 60, 75, 90, 120, 150, 180, 240, 300], id: \.self) { sec in
                    Text(verbatim: Clock.text(Double(sec))).tag(sec)
                }
            } label: {
                Label("Domyślna przerwa", systemImage: "timer")
            }
            .pickerStyle(.menu)
            Toggle(isOn: $store.haptics) { Label("Wibracje", systemImage: "iphone.radiowaves.left.and.right") }
            Toggle(isOn: $store.sound) { Label("Dźwięk na koniec przerwy", systemImage: "speaker.wave.2") }
            Divider()
            Button("Porzuć trening", systemImage: "trash", role: .destructive) { confirmDiscard = true }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .lvGlass(Circle())
        }
        .accessibilityLabel(Text("Menu treningu"))
    }

    private static func restChoices(including current: Int) -> [Int] {
        Array(Set([0, 30, 45, 60, 75, 90, 120, 150, 180, 240, 300, current])).sorted()
    }

    // MARK: Exercise title

    private func title(_ session: LiveSession, _ e: LiveExercise, index: Int) -> some View {
        let n = index + 1
        let total = session.exercises.count
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("Ćwiczenie \(n) z \(total)").lvCaps()
                if let g = e.item.groupId, let label = session.groupLabels[g] {
                    LVBadge(text: Text("Superseria \(label)"), colors: [LV.violet, LV.flame])
                }
                if e.item.sequence.count > 1 {
                    LVBadge(text: Text("Combo"), colors: [LV.ice, LV.violet])
                }
            }
            Text(verbatim: live.name(of: e))
                .font(.system(size: e.item.sequence.count > 1 ? 24 : 28, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
            if let variant = e.item.variant, !variant.isEmpty {
                Text(verbatim: variant).font(.system(size: 15)).foregroundStyle(LV.muted)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Active: NOW set N, hero, DONE strip

    private func measurement(_ e: LiveExercise) -> String {
        library.byId[e.countedExerciseId]?.measurement ?? "reps"
    }

    private func timerField(_ e: LiveExercise) -> LiveSession.TimerField? {
        switch measurement(e) {
        case "hold": return .hold
        case "distance_time": return .duration
        default: return nil
        }
    }

    private func holdTarget(_ e: LiveExercise) -> Double? {
        e.target?["targetHoldMax"] ?? e.target?["targetHoldMin"] ?? e.pending.holdSeconds
    }

    private func pendingBinding(_ index: Int) -> Binding<WorkoutSet> {
        Binding(
            get: { live.session?.exercises[safe: index]?.pending ?? WorkoutSet() },
            set: { v in live.update { s, _ in if s.exercises.indices.contains(index) { s.exercises[index].pending = v } } }
        )
    }

    private func activeStage(_ session: LiveSession, now: Double, mood: LiveMood) -> some View {
        let index = session.current
        let e = session.exercises[index]
        let done = e.item.sets.count
        let planned = max(e.plannedSets, done + 1)
        let setNumber = done + 1
        return VStack(spacing: 0) {
            title(session, e, index: index)
            Spacer(minLength: 16)
            VStack(spacing: 18) {
                // NOW: the set you are about to do. Never shows a logged set.
                HStack(spacing: 8) {
                    Circle().fill(mood.glow).frame(width: 8, height: 8).shadow(color: mood.glow, radius: 4)
                    Text("Teraz: seria \(setNumber) z \(planned)")
                        .font(.system(size: 14, weight: .heavy))
                        .tracking(1.2)
                        .textCase(.uppercase)
                }
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(mood.glow.opacity(0.16), in: Capsule())
                .overlay(Capsule().stroke(mood.glow.opacity(0.5), lineWidth: 1))
                hero(session, e, index: index, now: now)
                if let target = LiveFormat.target(e.target) {
                    Label { Text("Cel: \(target)") } icon: { Image(systemName: "scope") }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(LV.faint)
                }
            }
            Spacer(minLength: 16)
            doneStrip(e, index: index, planned: planned, mood: mood)
        }
    }

    @ViewBuilder
    private func hero(_ session: LiveSession, _ e: LiveExercise, index: Int, now: Double) -> some View {
        let pending = pendingBinding(index)
        if e.item.sequence.count > 1 {
            comboHero(session, e, index: index, now: now)
        } else if let field = timerField(e) {
            let running = session.setTimer
            let target = field == .hold ? holdTarget(e) : nil
            let recorded: Double? = field == .hold ? e.pending.holdSeconds : e.pending.durationSeconds.map(Double.init)
            let sec = running?.elapsed(now) ?? 0
            let reached = running != nil && target.map { sec >= $0 } == true
            let progress: Double = running == nil ? (timedKey == stopKey(e) ? 1 : 0) : target.map { sec / max($0, 1) } ?? sec.truncatingRemainder(dividingBy: 60) / 60
            VStack(spacing: 14) {
                LVRing(size: 240, stroke: 12, progress: reached ? 1 : progress,
                       from: reached || timedKey == stopKey(e) ? LV.lime : LV.gold,
                       to: reached || timedKey == stopKey(e) ? LV.sky : LV.flame) {
                    Group {
                        if running != nil {
                            if reached { Text("Cel osiągnięty") } else if field == .hold { Text("Trzymasz") } else { Text("Trwa") }
                        } else if timedKey == stopKey(e) {
                            Text("Twój czas")
                        } else if field == .hold {
                            Text("Cel utrzymania")
                        } else {
                            Text("Na czas")
                        }
                    }
                    .lvCaps()
                    Text(verbatim: Clock.text(running != nil ? sec.rounded(.down) : (recorded ?? target ?? 0)))
                        .font(.system(size: 64, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(reached ? AnyShapeStyle(LV.lime) : AnyShapeStyle(LV.text))
                        .padding(.top, 2)
                    if running != nil, let target {
                        Text(verbatim: "/ \(Clock.text(target))").font(.system(size: 14)).foregroundStyle(LV.muted).monospacedDigit()
                    }
                }
                if running == nil {
                    HStack(spacing: 10) {
                        ForEach(SetField.primary(measurement(e)).filter { $0 != .hold && $0 != .duration }) { f in
                            LVInlineStepper(field: f, set: pending)
                        }
                        if measurement(e) == "hold" && (e.pending.weightKg ?? 0) > 0 {
                            LVInlineStepper(field: .weight, set: pending)
                        }
                    }
                }
            }
        } else {
            let primary = SetField.primary(measurement(e))
            let main = primary.first ?? .reps
            VStack(spacing: 16) {
                HStack(alignment: .center, spacing: 18) {
                    LVStepButton(up: false, size: 54, disabled: (main.get(e.pending) ?? 0) <= main.range.lowerBound) {
                        withAnimation(.snappy) { main.bump(&pending.wrappedValue, up: false) }
                    }
                    Button {
                        sheet = .log(.pending, index: index, setIndex: e.item.sets.count)
                    } label: {
                        VStack(spacing: 2) {
                            Text(verbatim: main.display(main.get(e.pending)))
                                .font(.system(size: 132, weight: .black, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(LV.heroGradient)
                                .lineLimit(1)
                                .minimumScaleFactor(0.4)
                                .contentTransition(.numericText())
                                .background(
                                    Circle().fill(RadialGradient(colors: [LV.ember.opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: 120))
                                        .frame(width: 240, height: 240)
                                        .blur(radius: 20)
                                )
                            if let unit = main.unit {
                                Text(unit).lvCaps()
                            }
                        }
                        .frame(minWidth: 150)
                    }
                    .buttonStyle(LVPress(scale: 0.96))
                    .accessibilityLabel(Text("Zmień wartości serii"))
                    LVStepButton(up: true, size: 54, disabled: (main.get(e.pending) ?? 0) >= main.range.upperBound) {
                        withAnimation(.snappy) { main.bump(&pending.wrappedValue, up: true) }
                    }
                }
                .sensoryFeedback(.selection, trigger: main.get(e.pending))
                let secondary: [SetField] = Array(primary.dropFirst()) + ((e.pending.weightKg ?? 0) > 0 && !primary.contains(.weight) ? [SetField.weight] : [])
                if !secondary.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(secondary) { f in LVInlineStepper(field: f, set: pending) }
                    }
                }
            }
        }
    }

    private func measureId(_ id: String) -> String { library.byId[id]?.measurement ?? "reps" }

    private func ensureSteps() {
        live.update { s, _ in s.ensureComboPending(measurementOf: measureId) }
    }

    private func comboHero(_ session: LiveSession, _ e: LiveExercise, index: Int, now: Double) -> some View {
        let running = session.setTimer
        return VStack(spacing: 14) {
            ComboStepList(
                sequence: e.item.sequence,
                steps: e.pending.steps,
                nameOf: { library.byId[$0]?.name ?? $0 },
                measurementOf: measureId,
                runningIndex: timedStep?.index,
                runningSeconds: running.map { $0.elapsed(now) },
                onAdjust: { stepIndex, field, up in
                    live.update { s, _ in
                        guard s.exercises.indices.contains(index) else { return }
                        var steps = s.exercises[index].pending.steps
                        if steps.indices.contains(stepIndex) {
                            field.bumpStep(&steps[stepIndex], up: up)
                            s.exercises[index].pending.steps = steps
                            s.exercises[index].pending.applySteps(sequence: s.exercises[index].item.sequence)
                        }
                    }
                },
                onToggleTimer: { stepIndex, field in
                    if let timed = timedStep, timed.index == stepIndex, session.setTimer != nil {
                        live.update { s, t in
                            let seconds = max(1, (s.setTimer?.elapsed(t) ?? 0).rounded())
                            guard s.exercises.indices.contains(index) else { return }
                            var steps = s.exercises[index].pending.steps
                            if steps.indices.contains(stepIndex) {
                                field.putStep(seconds, into: &steps[stepIndex])
                                s.exercises[index].pending.steps = steps
                                s.exercises[index].pending.applySteps(sequence: s.exercises[index].item.sequence)
                            }
                            s.setTimer = nil
                        }
                        timedStep = nil
                    } else {
                        let target = e.pending.steps[safe: stepIndex].flatMap { field.stepValue($0) }
                        timedStep = (index: stepIndex, field: field)
                        live.update { s, t in s.startSetTimer(t, target: target) }
                    }
                }
            )
        }
    }

    /// DONE: logged sets of this exercise as lime-checked chips (tap = fix).
    private func doneStrip(_ e: LiveExercise, index: Int, planned: Int, mood: LiveMood) -> some View {
        VStack(spacing: 10) {
            LVDots(done: e.item.sets.count, total: planned, mood: mood)
            if e.item.sets.isEmpty {
                Text("Jeszcze nic nie zrobione").font(.system(size: 13)).foregroundStyle(LV.faint)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Zrobione").lvCaps(LV.lime.opacity(0.85))
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(e.item.sets.enumerated()), id: \.offset) { setIndex, set in
                                    DoneChip(number: setIndex + 1, text: LiveFormat.set(set), warmup: set.isWarmup) {
                                        sheet = .log(.edit, index: index, setIndex: setIndex)
                                    }
                                    .id(setIndex)
                                }
                            }
                        }
                        .onAppear { proxy.scrollTo(e.item.sets.count - 1, anchor: .trailing) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.bottom, 6)
    }

    // MARK: Rest: DONE chip on top, countdown ring, then what's NEXT

    private func upNext(_ session: LiveSession) -> (LiveExercise, Int)? {
        if let e = session.currentExercise, e.isOpen, e.item.sets.count < max(e.plannedSets, 1) {
            return (e, e.item.sets.count + 1)
        }
        if let i = session.nextOpenIndex(after: session.current) {
            return (session.exercises[i], session.exercises[i].item.sets.count + 1)
        }
        return nil
    }

    private func restStage(_ session: LiveSession, now: Double) -> some View {
        let rest = session.rest ?? LiveRest(startedAt: now, durationSec: 0, itemId: "", setIndex: 0)
        let left = rest.remaining(now)
        let over = left <= 0
        let lastIndex = session.exercises.firstIndex { $0.item.id == rest.itemId }
        let lastSet = lastIndex.flatMap { session.exercises[$0].item.sets[safe: rest.setIndex] }
        return VStack(spacing: 0) {
            if let lastIndex, let lastSet {
                let setNumber = rest.setIndex + 1
                Button {
                    sheet = .log(.edit, index: lastIndex, setIndex: rest.setIndex)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(.black)
                            .frame(width: 28, height: 28)
                            .background(LV.lime, in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Seria \(setNumber) zrobiona").font(.system(size: 13, weight: .bold)).foregroundStyle(LV.lime)
                            Text(verbatim: "\(live.name(of: session.exercises[lastIndex])) · \(LiveFormat.set(lastSet))")
                                .font(.system(size: 13)).foregroundStyle(LV.muted).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Text("Popraw").font(.system(size: 13, weight: .semibold)).foregroundStyle(LV.muted)
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 16)
                    .frame(height: 54)
                    .lvGlass(Capsule())
                }
                .buttonStyle(LVPress(scale: 0.97))
            }
            Spacer(minLength: 12)
            VStack(spacing: 18) {
                LVRing(size: 280, stroke: 16, progress: over ? 1 : left / max(1, rest.durationSec),
                       from: over ? LV.ember : LV.ice, to: over ? LV.flame : LV.violet) {
                    Group {
                        if over { Text("Czas start") } else if rest.pausedRemaining != nil { Text("Przerwa (pauza)") } else { Text("Przerwa") }
                    }
                    .lvCaps(over ? LV.gold : LV.muted)
                    Text(verbatim: Clock.text(left))
                        .font(.system(size: 84, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .foregroundStyle(over ? LV.gold : LV.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(verbatim: "/ \(Clock.text(rest.durationSec))")
                        .font(.system(size: 14)).foregroundStyle(LV.muted).monospacedDigit()
                }
                .scaleEffect(over && Int(now / 1000) % 2 == 0 ? 1.02 : 1)
                .animation(.easeInOut(duration: 0.5), value: Int(now / 1000))
                HStack(spacing: 12) {
                    LVPill(action: { live.tap(); live.update { s, t in s.adjustRest(by: -LiveSession.restStep, t) } }) {
                        Text(verbatim: "−15").monospacedDigit().frame(width: 48)
                    }
                    .accessibilityLabel(Text("Przerwa krótsza o 15 sekund"))
                    LVPill(action: { live.tap(); live.update { s, t in s.adjustRest(by: LiveSession.restStep, t) } }) {
                        Text(verbatim: "+15").monospacedDigit().frame(width: 48)
                    }
                    .accessibilityLabel(Text("Przerwa dłuższa o 15 sekund"))
                }
            }
            Spacer(minLength: 12)
            if let next = upNext(session) {
                let (e, setNo) = next
                NextCard(
                    caption: Text("Następnie"),
                    name: live.name(of: e),
                    detail: [String(localized: "Seria \(setNo) z \(max(e.plannedSets, setNo))"), LiveFormat.pendingText(e)].compactMap { $0 }.joined(separator: " · ")
                )
            }
        }
    }

    // MARK: Complete / empty

    private func completeStage(_ session: LiveSession) -> some View {
        let index = session.current
        let e = session.exercises[index]
        let allDone = session.nextOpenIndex(after: index) == nil
        let sets = e.item.sets
        let count = sets.count
        let reps = sets.reduce(0) { $0 + ($1.reps ?? 0) }
        let best = sets.compactMap(\.weightKg).max() ?? 0
        return VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 0) {
                Image(systemName: allDone ? "flag.checkered" : "checkmark")
                    .font(.system(size: 48, weight: .heavy))
                    .foregroundStyle(.black)
                    .frame(width: 112, height: 112)
                    .background(LiveMood.done.cta, in: Circle())
                    .shadow(color: LV.lime.opacity(0.6), radius: 40)
                Group {
                    if allDone { Text("Wszystko zrobione") } else if e.status == .skipped { Text("Pominięte") } else { Text("Ćwiczenie ukończone") }
                }
                .lvCaps()
                .padding(.top, 24)
                Text(verbatim: live.name(of: e))
                    .font(.system(size: 30, weight: .heavy))
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                if count > 0 {
                    HStack(spacing: 6) {
                        Text("\(count) serii")
                        if reps > 0 { Text(verbatim: "· \(reps)"); Text("powt.") }
                        if best > 0 { Text(verbatim: "· +\(best.short(2)) kg") }
                    }
                    .font(.system(size: 15)).foregroundStyle(LV.muted).monospacedDigit()
                    .padding(.top, 8)
                }
                HStack(spacing: 10) {
                    LVPill(action: {
                        live.tap()
                        live.update { s, _ in
                            guard s.exercises.indices.contains(index) else { return }
                            if s.exercises[index].status == .done || s.exercises[index].status == .skipped { s.reopenExercise(index) }
                            s.exercises[index].plannedSets = max(s.exercises[index].plannedSets, s.exercises[index].item.sets.count) + 1
                        }
                    }) {
                        Image(systemName: "plus")
                        Text("Jeszcze seria")
                    }
                    LVPill(action: { openAdd() }) {
                        Image(systemName: "plus")
                        Text("Ćwiczenie")
                    }
                }
                .padding(.top, 22)
            }
            Spacer()
            if !allDone, let upcoming = upNext(session) {
                let next = upcoming.0
                NextCard(
                    caption: Text("Następnie"),
                    name: live.name(of: next),
                    detail: [String(localized: "\(next.plannedSets) serii"), LiveFormat.pendingText(next)].compactMap { $0 }.joined(separator: " · ")
                )
            }
        }
    }

    private var emptyStage: some View {
        VStack(spacing: 10) {
            Spacer()
            Text("Trening bez planu").lvCaps()
            Text("Dodaj pierwsze ćwiczenie")
                .font(.system(size: 28, weight: .semibold))
                .multilineTextAlignment(.center)
            Text("Dodawaj ćwiczenia na bieżąco: wyszukiwarka wybacza literówki.")
                .font(.system(size: 15))
                .foregroundStyle(LV.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 290)
            Spacer()
        }
    }

    // MARK: Dock: side · ORB · side

    private func stopKey(_ e: LiveExercise) -> String { "\(e.id)-\(e.item.sets.count)" }

    @ViewBuilder
    private func dock(_ session: LiveSession, stage: Stage, now: Double, mood: LiveMood) -> some View {
        switch stage {
        case .empty:
            orbColumn(mood: mood, label: Text("Dodaj ćwiczenie"), a11y: "Dodaj ćwiczenie", icon: "plus") { openAdd() }
        case .rest:
            let over = (session.rest?.remaining(now) ?? 0) <= 0
            orbColumn(mood: mood, label: over ? Text("Start") : Text("Pomiń przerwę"), a11y: "Pomiń przerwę", icon: "arrow.right") {
                live.tap()
                live.update { s, t in s.closeRest(t) }
            }
        case .complete:
            let index = session.current
            let allDone = session.nextOpenIndex(after: index) == nil
            orbColumn(mood: mood, label: allDone ? Text("Zakończ trening") : Text("Następne ćwiczenie"),
                      a11y: allDone ? "Zakończ trening" : "Następne ćwiczenie",
                      icon: allDone ? "flag.checkered" : "arrow.right") {
                live.tap()
                if allDone {
                    if session.exercises[index].isOpen { live.update { s, t in s.finishExercise(index, t) } }  // finishExercise guards the index
                    requestFinish()
                } else {
                    forward = true
                    live.update { s, t in
                        guard s.exercises.indices.contains(index) else { return }
                        if s.exercises[index].isOpen { s.finishExercise(index, t) }
                        else if let n = s.nextOpenIndex(after: index) { s.goTo(n) }
                    }
                }
            }
        case .active:
            activeDock(session)
        }
    }

    private func activeDock(_ session: LiveSession) -> some View {
        let index = session.current
        let e = session.exercises[index]
        let field = timerField(e)
        let running = session.setTimer != nil
        let needsStart = field != nil && !running && timedKey != stopKey(e)
        let setNumber = e.item.sets.count + 1
        return VStack(spacing: 6) {
            HStack(alignment: .center, spacing: 22) {
                SideButton(icon: e.item.sets.isEmpty ? "forward.end" : "flag", label: e.item.sets.isEmpty ? Text("Pomiń") : Text("Koniec")) {
                    live.tap()
                    forward = true
                    live.update { s, t in
                        guard s.exercises.indices.contains(index) else { return }
                        if s.exercises[index].item.sets.isEmpty { s.skipExercise(index) } else { s.finishExercise(index, t) }
                    }
                }
                VStack(spacing: 8) {
                    if needsStart {
                        LVOrb(mood: .active, label: "Start stopera") {
                            live.tap()
                            live.update { s, t in s.startSetTimer(t, target: field == .hold ? holdTarget(e) : nil) }
                        } content: {
                            Image(systemName: "play.fill").font(.system(size: 38)).offset(x: 3)
                        }
                    } else if running, let field {
                        LVOrb(mood: .active, label: "Stop") {
                            live.success()
                            timedKey = stopKey(e)
                            live.update { s, t in s.stopSetTimer(t, field: field) }
                        } content: {
                            Image(systemName: "stop.fill").font(.system(size: 32))
                        }
                    } else {
                        LVOrb(mood: .active, label: "Zakończ serię") {
                            logSet(index: index)
                        } content: {
                            Image(systemName: "checkmark").font(.system(size: 42, weight: .heavy))
                        }
                    }
                    Group {
                        if needsStart { Text("Start stopera") } else if running { Text("Stop") } else { Text("Zakończ serię \(setNumber)") }
                    }
                    .font(.system(size: 14, weight: .bold))
                }
                SideButton(icon: "list.number", label: Text("Lista")) { sheet = .queue }
            }
            Group {
                if needsStart {
                    Button { sheet = .log(.log, index: index, setIndex: e.item.sets.count) } label: {
                        Text("Zapisz bez stopera").font(.system(size: 13, weight: .medium)).foregroundStyle(LV.muted)
                    }
                } else {
                    Label("lub przesuń w górę", systemImage: "chevron.up")
                        .font(.system(size: 12)).foregroundStyle(LV.faint)
                }
            }
            .frame(height: 28)
        }
    }

    private func orbColumn(mood: LiveMood, label: Text, a11y: LocalizedStringKey, icon: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            LVOrb(mood: mood, label: a11y, action: action) {
                Image(systemName: icon).font(.system(size: 38, weight: .bold))
            }
            label.font(.system(size: 14, weight: .bold))
        }
        .padding(.bottom, 34)
    }

    private func pausedOverlay(_ session: LiveSession, now: Double) -> some View {
        VStack(spacing: 22) {
            Text("Pauza").lvCaps()
            Text(verbatim: Clock.elapsed(session.elapsedMs(now)))
                .font(.system(size: 72, weight: .heavy, design: .rounded))
                .monospacedDigit()
            Text("Pauza: zegar treningu i przerwa są zatrzymane.")
                .font(.system(size: 14)).foregroundStyle(LV.muted)
                .multilineTextAlignment(.center).frame(maxWidth: 260)
            LVOrb(mood: .active, label: "Wznów") {
                live.tap()
                live.update { s, t in s.resume(t) }
            } content: {
                Image(systemName: "play.fill").font(.system(size: 38)).offset(x: 3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Material.ultraThinMaterial.opacity(0.9))
        .background(Color.black.opacity(0.55))
        .transition(.opacity)
    }

    // MARK: Actions

    private func logSet(index: Int) {
        guard let e = live.session?.exercises[safe: index] else { return }
        let field = timerField(e)
        live.update { s, t in
            if e.item.sequence.count > 1, let timed = timedStep, s.setTimer != nil {
                let seconds = max(1, (s.setTimer?.elapsed(t) ?? 0).rounded())
                if s.exercises.indices.contains(index) {
                    var steps = s.exercises[index].pending.steps
                    if steps.indices.contains(timed.index) {
                        timed.field.putStep(seconds, into: &steps[timed.index])
                        s.exercises[index].pending.steps = steps
                        s.exercises[index].pending.applySteps(sequence: s.exercises[index].item.sequence)
                    }
                    s.setTimer = nil
                }
            } else if let field, s.setTimer != nil {
                s.stopSetTimer(t, field: field)
            }
            s.logSet(t)
        }
        timedKey = nil
        timedStep = nil
        logged += 1
    }

    @ViewBuilder
    private func logSheet(_ mode: LiveLogSheet.Mode, index: Int, setIndex: Int) -> some View {
        if let e = live.session?.exercises[safe: index] {
            switch mode {
            case .edit:
                if let set = e.item.sets[safe: setIndex] {
                    LiveLogSheet(mode: .edit, title: live.name(of: e), setNumber: setIndex + 1, measurement: measurement(e), set: set,
                                 sequence: e.item.sequence, nameOf: { library.byId[$0]?.name ?? $0 }, measurementOf: measureId,
                                 onSave: { v in live.update { s, _ in s.updateSet(index, setIndex, v) } },
                                 onDelete: { live.update { s, _ in s.deleteSet(index, setIndex) } })
                }
            case .pending, .log:
                LiveLogSheet(mode: mode, title: live.name(of: e), setNumber: e.item.sets.count + 1, measurement: measurement(e), set: e.pending,
                             sequence: e.item.sequence, nameOf: { library.byId[$0]?.name ?? $0 }, measurementOf: measureId,
                             onSave: { v in
                                 live.update { s, _ in if s.exercises.indices.contains(index) { s.exercises[index].pending = v } }
                                 if mode == .log { logSet(index: index) }
                             })
            }
        }
    }

    private func openAdd(group: String? = nil) {
        addGroupId = group
        afterSheet { picking = true }
    }

    /// Runs `action` once an open sheet is gone (two sheets can't overlap).
    private func afterSheet(_ action: @escaping () -> Void) {
        if sheet == nil { action(); return }
        sheet = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: action)
    }

    private func add(_ exercise: Exercise, mode: AddMode) {
        let group = addGroupId
        live.tap()
        live.update { s, _ in
            if let group, let first = s.groupIndices(group).first {
                let previous = s.current
                s.current = first
                s.addExercise(exercise.id, mode: .superset, defaultRest: live.defaultRest)
                s.current = min(previous, s.exercises.count - 1)
            } else {
                s.addExercise(exercise.id, mode: mode, defaultRest: live.defaultRest)
            }
            s.ensureComboPending(measurementOf: { id in
                id == exercise.id ? exercise.measurement : measureId(id)
            })
            // A fresh exercise shows a real number to do, not a dash.
            if mode != .combo, let i = s.exercises.lastIndex(where: { $0.item.exerciseId == exercise.id && $0.item.sets.isEmpty }) {
                for f in SetField.primary(exercise.measurement) where f == .reps || f == .distance {
                    if f.get(s.exercises[i].pending) == nil { f.put(f.seed, into: &s.exercises[i].pending) }
                }
            }
        }
        addGroupId = nil
        picked = nil
    }

    private func requestFinish() {
        guard let session = live.session else { return }
        let clean = session.incomplete.isEmpty
        afterSheet { if clean { finishing = true } else { confirmUnfinished = true } }
    }
}

/// Lime check + "1 · 8 × +10 kg": a set that is done.
private struct DoneChip: View {
    let number: Int
    let text: String
    let warmup: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.black)
                    .frame(width: 20, height: 20)
                    .background(warmup ? LV.gold : LV.lime, in: Circle())
                Text(verbatim: "\(number)").font(.system(size: 13, weight: .heavy)).foregroundStyle(LV.lime)
                Text(verbatim: text).font(.system(size: 14, weight: .medium)).foregroundStyle(LV.muted).monospacedDigit()
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .frame(height: 34)
            .background(LV.lime.opacity(0.08), in: Capsule())
            .overlay(Capsule().stroke(LV.lime.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(LVPress(scale: 0.94))
        .accessibilityLabel(Text("Zrobiona seria \(number)"))
    }
}

private struct SideButton: View {
    let icon: String
    let label: Text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 56, height: 56)
                    .lvGlass(Circle())
                label.font(.system(size: 12, weight: .medium)).foregroundStyle(LV.muted)
            }
        }
        .buttonStyle(LVPress())
        .foregroundStyle(LV.text)
    }
}

private struct NextCard: View {
    let caption: Text
    let name: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                caption.lvCaps()
                Text(verbatim: name).font(.system(size: 18, weight: .bold)).lineLimit(1)
                if !detail.isEmpty {
                    Text(verbatim: detail).font(.system(size: 14)).foregroundStyle(LV.muted).lineLimit(1).monospacedDigit()
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").foregroundStyle(LV.faint)
        }
        .padding(16)
        .lvGlass(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.bottom, 8)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
