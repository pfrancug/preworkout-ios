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
            .toolbar(.visible, for: .tabBar)
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
            if addGroupId != nil {
                ExercisePickerView { exercise in
                    add(exercise, mode: .superset)
                }
            } else {
                // Placement stays on this same sheet. In 0.1.6 the picker was
                // dismissed and AddPlacementSheet was presented next; that
                // transition aborts in UIKeyboardLayoutGuide when search is up
                // (TestFlight 0.1.6 builds 29 and 31).
                ExercisePickerView { _ in } placement: { exercise in
                    AddPlacementSheet(
                        exerciseName: exercise.name,
                        currentName: live.session?.currentExercise.map { live.name(of: $0) } ?? "",
                        hasCurrent: live.session?.currentExercise != nil
                    ) { mode, asSession in
                        add(exercise, mode: mode, asSession: asSession)
                    }
                }
            }
        }
        // Alerts (centered, no arrow): these are opened from menus and sheets,
        // so there is no stable view a popover arrow could point at.
        .alert("Porzucić ten trening?", isPresented: $confirmDiscard) {
            Button("Porzuć trening", role: .destructive) { live.discard() }
            Button("Anuluj", role: .cancel) {}
        } message: {
            Text("Wszystkie serie zapisane w tej sesji przepadną. Tego nie da się cofnąć.")
        }
        .alert("Nie można jeszcze zakończyć", isPresented: $confirmUnfinished) {
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
                    case .empty: emptyStage.browsable(browseGesture(session))
                    case .active:
                        if session.currentExercise?.item.isSession == true {
                            sessionStage(session, now: now).browsable(browseGesture(session))
                        } else {
                            activeStage(session, now: now, mood: md)
                        }
                    case .rest: restStage(session, now: now).browsable(browseGesture(session))
                    case .complete: completeStage(session).browsable(browseGesture(session))
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
                dock(session, stage: st, now: now, mood: md)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
            .animation(LV.spring, value: key)
            if session.isPaused { pausedOverlay(session, now: now) }
        }
        .foregroundStyle(LV.text)
    }

    /// Horizontal swipe on the stage browses exercises. Runs alongside the
    /// buttons (simultaneous), but only a clearly horizontal drag counts:
    /// 24 pt before it starts, then ≥ 60 pt sideways (or a quick flick) and
    /// at least twice as far sideways as up/down. − / + and the number give
    /// up after 10 pt of movement, so a swipe never changes a value.
    private func browseGesture(_ session: LiveSession) -> some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { g in
                let dx = g.translation.width, dy = g.translation.height
                let far = abs(dx) > 60 || (abs(g.predictedEndTranslation.width) > 160 && abs(dx) > 30)
                guard far, abs(dx) > abs(dy) * 2 else { return }
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
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .fixedSize(horizontal: true, vertical: false)
                        Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 12))
                            .opacity(session.isPaused ? 1 : 0.6)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .lvGlass(Capsule())
                }
                .buttonStyle(LVPress(scale: 0.95))
                .layoutPriority(1)
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
            Picker(selection: $store.defaultTimerMode) {
                ForEach(TimedSetMode.allCases) { mode in
                    Text(verbatim: mode.title).tag(mode)
                }
            } label: {
                Label("Domyślny tryb timera", systemImage: "stopwatch")
            }
            .pickerStyle(.menu)
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

    @ViewBuilder
    private func activeStage(_ session: LiveSession, now: Double, mood: LiveMood) -> some View {
        if let e = session.currentExercise {
        let index = session.current
        let done = e.item.sets.count
        let planned = max(e.plannedSets, done + 1)
        let setNumber = done + 1
        VStack(spacing: 0) {
            VStack(spacing: 0) {
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
            }
            .browsable(browseGesture(session))
            doneStrip(e, index: index, planned: planned, mood: mood)
        }
        }
    }

    @ViewBuilder
    private func hero(_ session: LiveSession, _ e: LiveExercise, index: Int, now: Double) -> some View {
        let pending = pendingBinding(index)
        if e.item.sequence.count > 1 {
            comboHero(session, e, index: index, now: now)
        } else if let field = timerField(e) {
            TimedSetHero(
                session: session,
                exercise: e,
                field: field,
                measurement: measurement(e),
                now: now,
                pending: pending,
                timedJustFinished: timedKey == stopKey(e)
            )
        } else {
            let primary = SetField.primary(measurement(e))
            let main = primary.first ?? .reps
            VStack(spacing: 16) {
                HStack(alignment: .center, spacing: 4) {
                    LVStepButton(up: false, size: 54, hit: 68, disabled: (main.get(e.pending) ?? 0) <= main.range.lowerBound) {
                        withAnimation(.snappy) { main.bump(&pending.wrappedValue, up: false) }
                    }
                    // Plain tap only (a tap gesture fails once the finger moves),
                    // hit area = the number itself, the glow is not touchable.
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
                                    .allowsHitTesting(false)
                            )
                        if let unit = main.unit {
                            Text(unit).lvCaps()
                        }
                    }
                    .frame(minWidth: 130)
                    .contentShape(Rectangle())
                    .onTapGesture { sheet = .log(.pending, index: index, setIndex: e.item.sets.count) }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(Text("Zmień wartości serii"))
                    LVStepButton(up: true, size: 54, hit: 68, disabled: (main.get(e.pending) ?? 0) >= main.range.upperBound) {
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
        let mode = live.timerMode(for: e.item.exerciseId)
        return VStack(spacing: 14) {
            TimerModePicker(mode: comboModeBinding(e), enabled: running == nil)
            if mode == .countdown, running == nil {
                CountdownTargetEditor(seconds: Binding(
                    get: { live.countdownPrefill(for: e, field: .hold) },
                    set: { live.setCountdownTarget($0, for: e.item.exerciseId) }
                ))
            }
            ComboStepList(
                sequence: e.item.sequence,
                steps: e.pending.steps,
                nameOf: { library.byId[$0]?.name ?? $0 },
                measurementOf: measureId,
                runningIndex: timedStep?.index,
                runningSeconds: running.map { $0.displaySeconds(now) },
                runningOvertime: running?.isOvertime(now) == true,
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
                onToggleTimer: mode == .manual ? nil : { stepIndex, field in
                    if let timed = timedStep, timed.index == stepIndex, session.setTimer != nil {
                        live.update { s, t in
                            let seconds = Double(s.setTimer?.recordedSeconds(t) ?? 1)
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
                        let countsDown = mode == .countdown
                        let target = countsDown
                            ? live.countdownPrefill(for: e, field: field == .duration ? .duration : .hold)
                            : e.pending.steps[safe: stepIndex].flatMap { field.stepValue($0) }
                        if countsDown, let target {
                            live.setCountdownTarget(target, for: e.item.exerciseId)
                        }
                        timedStep = (index: stepIndex, field: field)
                        live.update { s, t in s.startSetTimer(t, target: target, countsDown: countsDown) }
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

    // MARK: Session block

    @ViewBuilder
    private func sessionStage(_ session: LiveSession, now: Double) -> some View {
        if let e = session.currentExercise {
        let elapsed = Double(e.pending.durationSeconds ?? 0) + (session.setTimer?.elapsed(now) ?? 0)
        SessionStage(
            name: live.name(of: e),
            elapsed: elapsed,
            running: session.setTimer != nil,
            attempts: e.pending.attempts ?? 0,
            note: e.pending.notes,
            onStart: {
                live.tap()
                live.update { s, t in s.startSessionClock(t) }
            },
            onPause: {
                live.tap()
                live.update { s, t in s.pauseSessionClock(t) }
            },
            onResume: {
                live.tap()
                live.update { s, t in s.startSessionClock(t) }
            },
            onAttempts: { n in
                live.update { s, _ in
                    guard s.exercises.indices.contains(s.current) else { return }
                    s.exercises[s.current].pending.attempts = n > 0 ? n : nil
                }
            },
            onNote: { text in
                live.update { s, _ in
                    guard s.exercises.indices.contains(s.current) else { return }
                    s.exercises[s.current].pending.notes = text
                }
            }
        )
        }
    }

    // MARK: Complete / empty

    @ViewBuilder
    private func completeStage(_ session: LiveSession) -> some View {
        if let e = session.currentExercise {
        let index = session.current
        let allDone = session.nextOpenIndex(after: index) == nil
        let sets = e.item.sets
        let count = sets.count
        let reps = sets.reduce(0) { $0 + ($1.reps ?? 0) }
        let best = sets.compactMap(\.weightKg).max() ?? 0
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 0) {
                if e.status == .skipped {
                    Image(systemName: "forward.end")
                        .font(.system(size: 44, weight: .heavy))
                        .foregroundStyle(LV.text)
                        .frame(width: 112, height: 112)
                        .lvGlass(Circle())
                } else {
                    Image(systemName: allDone ? "flag.checkered" : "checkmark")
                        .font(.system(size: 48, weight: .heavy))
                        .foregroundStyle(.black)
                        .frame(width: 112, height: 112)
                        .background(LiveMood.done.cta, in: Circle())
                        .shadow(color: LV.lime.opacity(0.6), radius: 40)
                }
                Group {
                    if e.status == .skipped { Text("Pominięte") } else if allDone { Text("Wszystko zrobione") } else { Text("Ćwiczenie ukończone") }
                }
                .lvCaps()
                .padding(.top, 24)
                Text(verbatim: live.name(of: e))
                    .font(.system(size: 30, weight: .heavy))
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                if e.item.isSession, e.status != .skipped {
                    Text(SessionFormat.summary(e.item))
                        .font(.system(size: 15)).foregroundStyle(LV.muted).monospacedDigit()
                        .padding(.top, 8)
                } else if count > 0 {
                    HStack(spacing: 6) {
                        Text("\(count) serii")
                        if reps > 0 { Text(verbatim: "· \(reps)"); Text("powt.") }
                        if best > 0 { Text(verbatim: "· +\(best.short(2)) kg") }
                    }
                    .font(.system(size: 15)).foregroundStyle(LV.muted).monospacedDigit()
                    .padding(.top, 8)
                }
                HStack(spacing: 10) {
                    if e.status == .skipped {
                        // Skipped exercises only offer restore, never "one more set".
                        LVPill(action: {
                            live.tap()
                            live.update { s, _ in s.restoreExercise(index) }
                        }) {
                            Image(systemName: "arrow.uturn.backward")
                            Text("Przywróć")
                        }
                    } else if !e.item.isSession {
                        // One more set = set N+1 of N+1, never back to set 1.
                        LVPill(action: {
                            live.tap()
                            live.update { s, _ in s.addOneMoreSet(index) }
                        }) {
                            Image(systemName: "plus")
                            Text("Jeszcze seria")
                        }
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
                    detail: next.item.isSession
                        ? String(localized: "Sesja")
                        : [String(localized: "\(next.plannedSets) serii"), LiveFormat.pendingText(next)].compactMap { $0 }.joined(separator: " · ")
                )
            }
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
                    if session.exercises[safe: index]?.isOpen == true { live.update { s, t in s.finishExercise(index, t) } }
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
            if session.currentExercise?.item.isSession == true {
                sessionDock(session, now: now, mood: mood)
            } else {
                activeDock(session)
            }
        }
    }

    @ViewBuilder
    private func sessionDock(_ session: LiveSession, now: Double, mood: LiveMood) -> some View {
        if let e = session.currentExercise {
        let index = session.current
        let elapsed = Double(e.pending.durationSeconds ?? 0) + (session.setTimer?.elapsed(now) ?? 0)
        let canFinish = elapsed >= 1
        VStack(spacing: 6) {
            HStack(alignment: .center, spacing: 22) {
                SideButton(icon: "forward.end", label: Text("Pomiń")) {
                    live.tap()
                    forward = true
                    live.update { s, t in
                        guard s.exercises.indices.contains(index) else { return }
                        s.setTimer = nil
                        s.skipExercise(index)
                    }
                }
                VStack(spacing: 8) {
                    LVOrb(mood: mood, label: "Zakończ sesję") {
                        guard canFinish else { return }
                        live.tap()
                        forward = true
                        live.update { s, t in s.finishSession(index, t) }
                    } content: {
                        Image(systemName: "checkmark").font(.system(size: 42, weight: .heavy))
                    }
                    .opacity(canFinish ? 1 : 0.4)
                    .disabled(!canFinish)
                    Text("Zakończ sesję").font(.system(size: 14, weight: .bold))
                }
                SideButton(icon: "list.number", label: Text("Lista")) { sheet = .queue }
            }
            Color.clear.frame(height: 28)
        }
        }
    }

    @ViewBuilder
    private func activeDock(_ session: LiveSession) -> some View {
        if let e = session.currentExercise {
        let index = session.current
        let field = timerField(e)
        let running = session.setTimer != nil
        let mode = field != nil ? live.timerMode(for: e.item.exerciseId) : nil
        let needsStart = field != nil && !running && timedKey != stopKey(e) && mode != .manual
        let setNumber = e.item.sets.count + 1
        VStack(spacing: 6) {
            HStack(alignment: .center, spacing: 22) {
                SideButton(icon: e.item.sets.isEmpty ? "forward.end" : "flag", label: e.item.sets.isEmpty ? Text("Pomiń") : Text("Koniec")) {
                    if running && field != nil {
                        // A running hold is a set in progress: save it, don't drop it.
                        logSet(index: index)
                        return
                    }
                    live.tap()
                    forward = true
                    live.update { s, t in
                        guard s.exercises.indices.contains(index) else { return }
                        if s.exercises[index].item.sets.isEmpty { s.skipExercise(index) } else { s.finishExercise(index, t) }
                    }
                }
                VStack(spacing: 8) {
                    if needsStart {
                        LVOrb(mood: .active, label: LocalizedStringKey(mode == .countdown ? "Start odliczania" : "Start stopera")) {
                            startSetTimer(e, field: field)
                        } content: {
                            Image(systemName: "play.fill").font(.system(size: 38)).offset(x: 3)
                        }
                    } else if running, field != nil {
                        // Stop saves the set with the measured time and starts the
                        // rest right away; "Pomiń" during the rest only skips the rest.
                        LVOrb(mood: .active, label: "Stop i zapisz") {
                            logSet(index: index)
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
                        if needsStart {
                            if mode == .countdown { Text("Start odliczania") } else { Text("Start stopera") }
                        } else if running {
                            Text("Stop i zapisz")
                        } else {
                            Text("Zakończ serię \(setNumber)")
                        }
                    }
                    .font(.system(size: 14, weight: .bold))
                }
                SideButton(icon: "list.number", label: Text("Lista")) { sheet = .queue }
            }
            Group {
                if needsStart, mode != .countdown {
                    Button { sheet = .log(.log, index: index, setIndex: e.item.sets.count) } label: {
                        Text("Zapisz bez stopera").font(.system(size: 13, weight: .medium)).foregroundStyle(LV.muted)
                    }
                } else {
                    Color.clear
                }
            }
            .frame(height: 28)
        }
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
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 24)
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

    private func comboModeBinding(_ e: LiveExercise) -> Binding<TimedSetMode> {
        Binding(
            get: { live.timerMode(for: e.item.exerciseId) },
            set: { live.setTimerMode($0, for: e.item.exerciseId) }
        )
    }

    private func startSetTimer(_ e: LiveExercise, field: LiveSession.TimerField?) {
        live.tap()
        let mode = live.timerMode(for: e.item.exerciseId)
        if mode == .countdown {
            live.prepareCountdownNotifications()
            let target = live.countdownPrefill(for: e, field: field ?? .hold)
            live.setCountdownTarget(target, for: e.item.exerciseId)
            live.update { s, t in s.startSetTimer(t, target: target, countsDown: true) }
        } else {
            live.update { s, t in s.startSetTimer(t, target: field == .hold ? holdTarget(e) : nil, countsDown: false) }
        }
    }

    private func logSet(index: Int) {
        guard let e = live.session?.exercises[safe: index] else { return }
        let field = timerField(e)
        live.update { s, t in
            if e.item.sequence.count > 1, let timed = timedStep, s.setTimer != nil {
                let seconds = Double(s.setTimer?.recordedSeconds(t) ?? 1)
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
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            action()
        }
    }

    private func add(_ exercise: Exercise, mode: AddMode, asSession: Bool = false) {
        let group = addGroupId
        live.tap()
        live.update { s, _ in
            if let group, let first = s.groupIndices(group).first {
                let previous = s.current
                s.current = first
                s.addExercise(exercise.id, mode: .superset, defaultRest: live.defaultRest)
                s.current = s.exercises.isEmpty ? 0 : min(max(previous, 0), s.exercises.count - 1)
            } else {
                s.addExercise(exercise.id, mode: mode, defaultRest: live.defaultRest, asSession: asSession)
            }
            s.ensureComboPending(measurementOf: { id in
                id == exercise.id ? exercise.measurement : measureId(id)
            })
            // A fresh exercise shows a real number to do, not a dash.
            if !asSession, mode != .combo, let i = s.exercises.lastIndex(where: { $0.item.exerciseId == exercise.id && $0.item.sets.isEmpty }) {
                for f in SetField.primary(exercise.measurement) where f == .reps || f == .distance {
                    if f.get(s.exercises[i].pending) == nil { f.put(f.seed, into: &s.exercises[i].pending) }
                }
            }
        }
        addGroupId = nil
        picking = false
    }

    private func requestFinish() {
        guard live.session != nil else { return }
        // Stop a running set/session timer now, before the sheet-dismiss delay,
        // and record that set as if the user had tapped stop.
        let field: LiveSession.TimerField?
        if let e = live.session?.currentExercise, !e.item.isSession {
            field = timerField(e)
        } else {
            field = nil
        }
        let combo = timedStep
        live.update { s, t in
            s.commitInProgressForFinish(t, timerField: field, comboStep: combo)
        }
        timedKey = nil
        timedStep = nil
        let clean = live.session?.incomplete.isEmpty ?? true
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
