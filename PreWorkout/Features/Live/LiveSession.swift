import Foundation

/// Live workout session. Same JSON shape and rules as the web app's
/// `src/lib/live/session.ts` (`ILiveSession`, version 1), so a session left in
/// the server drafts table (`workout` / `live-session`) can be resumed here.
/// Every clock is stored as epoch milliseconds, never as a running counter, so
/// killing the app or locking the phone never loses or skews time.

/// Untyped JSON value (plan target copy, kept verbatim).
enum JSONValue: Codable, Hashable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    subscript(key: String) -> Double? {
        if case .object(let o) = self, case .number(let n)? = o[key] { return n }
        return nil
    }
}

enum LiveStatus: String, Codable { case pending, active, done, skipped }

enum AddMode: String, CaseIterable, Identifiable { case end, next, superset, combo; var id: String { rawValue } }

struct LiveExercise: Codable, Hashable, Identifiable {
    var item: WorkoutExercise
    var target: JSONValue?
    var plannedSets: Int
    var restSeconds: Int
    var status: LiveStatus = .pending
    var startedAt: Double?
    var finishedAt: Double?
    var pending: WorkoutSet

    var id: String { item.id }
    var isOpen: Bool { status == .pending || status == .active }

    /// Measurement source: the last step of a combo.
    var countedExerciseId: String {
        item.sequence.count > 1 ? item.sequence[item.sequence.count - 1] : item.exerciseId
    }

    var hasIncompleteSets: Bool {
        isOpen && item.sets.count < max(1, plannedSets)
    }

    init(item: WorkoutExercise, target: JSONValue? = nil, defaultRest: Int) {
        var item = item
        item.sets = []
        self.item = item
        self.target = target
        plannedSets = max(1, Int(target?["targetSets"] ?? 3))
        restSeconds = target?["restSeconds"].map { Int($0) } ?? defaultRest
        var pending = WorkoutSet()
        if let target {
            pending.reps = (target["targetRepsMax"] ?? target["targetRepsMin"]).map { Int($0) }
            pending.holdSeconds = target["targetHoldMax"] ?? target["targetHoldMin"]
            pending.weightKg = target["targetWeightKg"]
            pending.rpe = target["targetRpe"]
        }
        self.pending = pending
    }

    private enum CodingKeys: String, CodingKey {
        case item, target, plannedSets, restSeconds, status, startedAt, finishedAt, pending
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        item = try c.decode(WorkoutExercise.self, forKey: .item)
        target = try c.decodeIfPresent(JSONValue.self, forKey: .target)
        if target == .null { target = nil }
        plannedSets = try c.decodeIfPresent(Int.self, forKey: .plannedSets) ?? 3
        restSeconds = try c.decodeIfPresent(Int.self, forKey: .restSeconds) ?? LiveSession.defaultRestSeconds
        status = try c.decodeIfPresent(LiveStatus.self, forKey: .status) ?? .pending
        startedAt = try c.decodeIfPresent(Double.self, forKey: .startedAt)
        finishedAt = try c.decodeIfPresent(Double.self, forKey: .finishedAt)
        pending = try c.decodeIfPresent(WorkoutSet.self, forKey: .pending) ?? WorkoutSet()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(item, forKey: .item)
        try c.encode(target ?? .null, forKey: .target)
        try c.encode(plannedSets, forKey: .plannedSets)
        try c.encode(restSeconds, forKey: .restSeconds)
        try c.encode(status, forKey: .status)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(finishedAt, forKey: .finishedAt)
        try c.encode(pending, forKey: .pending)
    }
}

struct LiveRest: Codable, Hashable {
    var startedAt: Double
    var durationSec: Double
    /// Seconds left when paused (nil = running).
    var pausedRemaining: Double?
    /// The set this rest follows: it gets the actual rest time.
    var itemId: String
    var setIndex: Int
    var alerted: Bool

    func remaining(_ now: Double) -> Double { pausedRemaining ?? durationSec - (now - startedAt) / 1000 }

    private enum CodingKeys: String, CodingKey { case startedAt, durationSec, pausedRemaining, itemId, setIndex, alerted }
    init(startedAt: Double, durationSec: Double, itemId: String, setIndex: Int) {
        self.startedAt = startedAt; self.durationSec = durationSec; self.itemId = itemId; self.setIndex = setIndex
        pausedRemaining = nil; alerted = false
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(startedAt, forKey: .startedAt); try c.encode(durationSec, forKey: .durationSec)
        try c.encode(pausedRemaining, forKey: .pausedRemaining); try c.encode(itemId, forKey: .itemId)
        try c.encode(setIndex, forKey: .setIndex); try c.encode(alerted, forKey: .alerted)
    }
}

struct LiveSetTimer: Codable, Hashable {
    var startedAt: Double
    var pausedElapsed: Double?
    var targetSec: Double?
    var alerted: Bool

    func elapsed(_ now: Double) -> Double { pausedElapsed ?? max(0, (now - startedAt) / 1000) }

    private enum CodingKeys: String, CodingKey { case startedAt, pausedElapsed, targetSec, alerted }
    init(startedAt: Double, targetSec: Double?) {
        self.startedAt = startedAt; self.targetSec = targetSec; pausedElapsed = nil; alerted = false
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(startedAt, forKey: .startedAt); try c.encode(pausedElapsed, forKey: .pausedElapsed)
        try c.encode(targetSec, forKey: .targetSec); try c.encode(alerted, forKey: .alerted)
    }
}

struct LiveSession: Codable, Hashable {
    static let defaultRestSeconds = 90
    static let restStep = 15
    static let draftKey = "live-session"

    var version = 1
    var id: String
    var date: String
    var title: String
    var planId: String?
    var planDayId: String?
    var startedAt: Double
    var pausedAt: Double?
    var pausedMs: Double
    var exercises: [LiveExercise]
    var current: Int
    var rest: LiveRest?
    var setTimer: LiveSetTimer?
    var notes: String
    var rpe: Double?

    private enum CodingKeys: String, CodingKey {
        case version, id, date, title, planId, planDayId, startedAt, pausedAt, pausedMs
        case exercises, current, rest, setTimer, notes, rpe
    }

    /// Ad hoc session (exercises are added while training).
    init(date: String, now: Double) {
        id = newId(); self.date = date; title = ""; planId = nil; planDayId = nil
        startedAt = now; pausedAt = nil; pausedMs = 0; exercises = []; current = 0
        rest = nil; setTimer = nil; notes = ""; rpe = nil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        guard version == 1 else { throw DecodingError.dataCorruptedError(forKey: .version, in: c, debugDescription: "version") }
        id = try c.decode(String.self, forKey: .id)
        date = try c.decode(String.self, forKey: .date)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        planId = try c.decodeIfPresent(String.self, forKey: .planId)
        planDayId = try c.decodeIfPresent(String.self, forKey: .planDayId)
        startedAt = try c.decode(Double.self, forKey: .startedAt)
        pausedAt = try c.decodeIfPresent(Double.self, forKey: .pausedAt)
        pausedMs = try c.decodeIfPresent(Double.self, forKey: .pausedMs) ?? 0
        exercises = try c.decode([LiveExercise].self, forKey: .exercises)
        current = try c.decodeIfPresent(Int.self, forKey: .current) ?? 0
        rest = try c.decodeIfPresent(LiveRest.self, forKey: .rest)
        setTimer = try c.decodeIfPresent(LiveSetTimer.self, forKey: .setTimer)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        rpe = try c.decodeIfPresent(Double.self, forKey: .rpe)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version); try c.encode(id, forKey: .id); try c.encode(date, forKey: .date)
        try c.encode(title, forKey: .title); try c.encode(planId, forKey: .planId); try c.encode(planDayId, forKey: .planDayId)
        try c.encode(startedAt, forKey: .startedAt); try c.encode(pausedAt, forKey: .pausedAt); try c.encode(pausedMs, forKey: .pausedMs)
        try c.encode(exercises, forKey: .exercises); try c.encode(current, forKey: .current)
        try c.encode(rest, forKey: .rest); try c.encode(setTimer, forKey: .setTimer)
        try c.encode(notes, forKey: .notes); try c.encode(rpe, forKey: .rpe)
    }

    static var nowMs: Double { Date().timeIntervalSince1970 * 1000 }

    // MARK: Clocks

    var isPaused: Bool { pausedAt != nil }
    func elapsedMs(_ now: Double) -> Double { max(0, (pausedAt ?? now) - startedAt - pausedMs) }
    var currentExercise: LiveExercise? { exercises.indices.contains(current) ? exercises[current] : nil }

    mutating func pause(_ now: Double) {
        guard pausedAt == nil else { return }
        pausedAt = now
        if var r = rest { r.pausedRemaining = r.remaining(now); rest = r }
        if var t = setTimer { t.pausedElapsed = t.elapsed(now); setTimer = t }
    }

    mutating func resume(_ now: Double) {
        guard let p = pausedAt else { return }
        pausedAt = nil
        pausedMs += now - p
        if var r = rest {
            r.startedAt = now - (r.durationSec - (r.pausedRemaining ?? 0)) * 1000
            r.pausedRemaining = nil
            rest = r
        }
        if var t = setTimer {
            t.startedAt = now - (t.pausedElapsed ?? 0) * 1000
            t.pausedElapsed = nil
            setTimer = t
        }
    }

    // MARK: Exercises

    private func clamp(_ i: Int) -> Int { max(0, min(i, exercises.count - 1)) }

    func nextOpenIndex(after from: Int) -> Int? {
        if from + 1 < exercises.count {
            for i in (from + 1)..<exercises.count where exercises[i].isOpen { return i }
        }
        for i in 0..<min(from, exercises.count) where exercises[i].isOpen { return i }
        return nil
    }

    mutating func startExercise(_ index: Int, _ now: Double) {
        guard exercises.indices.contains(index) else { return }
        exercises[index].status = .active
        if exercises[index].startedAt == nil { exercises[index].startedAt = now }
        exercises[index].finishedAt = nil
        if index != current { setTimer = nil }
        current = index
    }

    mutating func goTo(_ index: Int) {
        guard index != current, !exercises.isEmpty else { return }
        current = clamp(index)
        setTimer = nil
    }

    mutating func finishExercise(_ index: Int, _ now: Double) {
        guard exercises.indices.contains(index) else { return }
        exercises[index].status = exercises[index].item.sets.isEmpty ? .skipped : .done
        exercises[index].finishedAt = now
        if let target = nextOpenIndex(after: index) { goTo(target) } else { setTimer = nil }
    }

    mutating func skipExercise(_ index: Int) {
        guard exercises.indices.contains(index) else { return }
        exercises[index].status = .skipped
        if index == current, let target = nextOpenIndex(after: index) { goTo(target) }
    }

    mutating func reopenExercise(_ index: Int) {
        guard exercises.indices.contains(index) else { return }
        exercises[index].status = exercises[index].item.sets.isEmpty ? .pending : .active
        exercises[index].finishedAt = nil
    }

    /// Restores a skipped exercise and makes it current, on its first
    /// unfinished set (set 1 of the plan when nothing was logged). Does
    /// not add a set — "Jeszcze seria" is only for completed exercises.
    mutating func restoreExercise(_ index: Int) {
        guard exercises.indices.contains(index) else { return }
        reopenExercise(index)
        exercises[index].plannedSets = max(exercises[index].plannedSets, 1)
        if index != current { setTimer = nil }
        current = index
    }

    /// "One more set": the next set becomes N+1 of N+1 and is current.
    mutating func addOneMoreSet(_ index: Int) {
        guard exercises.indices.contains(index) else { return }
        reopenExercise(index)
        exercises[index].plannedSets = exercises[index].item.sets.count + 1
        if index != current { setTimer = nil }
        current = index
    }

    mutating func moveExercise(_ index: Int, by dir: Int) {
        let to = index + dir
        guard exercises.indices.contains(index), exercises.indices.contains(to) else { return }
        exercises.swapAt(index, to)
        current = current == index ? to : current == to ? index : current
        normalizeGroupContiguity()
    }

    mutating func removeExercise(_ index: Int) {
        guard exercises.indices.contains(index) else { return }
        let removed = exercises.remove(at: index)
        let next = index < current ? current - 1 : min(current, exercises.count - 1)
        if rest?.itemId == removed.item.id { rest = nil }
        if index == current { setTimer = nil }
        current = max(0, next)
    }

    /// Adds a library exercise at the end, right after the current one, in a
    /// superset with the current one, or as the next step of the current combo.
    mutating func addExercise(_ exerciseId: String, mode: AddMode, defaultRest: Int) {
        let cur = currentExercise
        if mode == .combo, let cur {
            let seq = cur.item.sequence.count > 1 ? cur.item.sequence + [exerciseId] : [cur.item.exerciseId, exerciseId]
            exercises[current].item.sequence = seq
            return
        }
        var fresh = LiveExercise(item: WorkoutExercise(exerciseId: exerciseId), defaultRest: cur?.restSeconds ?? defaultRest)
        if mode == .superset, let cur {
            let groupId = cur.item.groupId ?? newId()
            let members = groupIndices(groupId)
            let last = members.last ?? current
            let ref = exercises[members.first ?? current]
            fresh.plannedSets = ref.plannedSets
            fresh.restSeconds = ref.restSeconds
            fresh.item.groupId = groupId
            exercises.insert(fresh, at: last + 1)
            if cur.item.groupId == nil, let i = exercises.firstIndex(where: { $0.item.id == cur.item.id }) {
                exercises[i].item.groupId = groupId
            }
            return
        }
        if cur == nil || mode == .end {
            exercises.append(fresh)
        } else {
            exercises.insert(fresh, at: current + 1)
        }
    }

    func groupIndices(_ groupId: String) -> [Int] {
        exercises.indices.filter { exercises[$0].item.groupId == groupId }
    }

    private mutating func collapseSingletons() {
        var counts: [String: Int] = [:]
        for e in exercises { if let g = e.item.groupId { counts[g, default: 0] += 1 } }
        for i in exercises.indices {
            if let g = exercises[i].item.groupId, counts[g, default: 0] <= 1 { exercises[i].item.groupId = nil }
        }
    }

    /// Members no longer in one contiguous block leave the group (longest run stays).
    private mutating func normalizeGroupContiguity() {
        var seen: [String] = []
        for e in exercises { if let g = e.item.groupId, !seen.contains(g) { seen.append(g) } }
        for g in seen {
            let idx = groupIndices(g)
            guard idx.count > 1 else { continue }
            var bestStart = 0, bestLen = 1, runStart = 0
            for k in 1...idx.count {
                if k == idx.count || idx[k] != idx[k - 1] + 1 {
                    let len = k - runStart
                    if len > bestLen { bestLen = len; bestStart = runStart }
                    runStart = k
                }
            }
            let keep = Set(idx[bestStart..<(bestStart + bestLen)])
            for i in idx where !keep.contains(i) { exercises[i].item.groupId = nil }
        }
        collapseSingletons()
    }

    /// Leaves the superset (sets stay; a leftover single member dissolves).
    mutating func ungroup(_ index: Int) {
        guard exercises.indices.contains(index), exercises[index].item.groupId != nil else { return }
        exercises[index].item.groupId = nil
        collapseSingletons()
    }

    /// Turns a combo back into separate exercises; logged sets stay on the first step.
    mutating func splitCombo(_ index: Int) {
        guard exercises.indices.contains(index), exercises[index].item.sequence.count > 1 else { return }
        let e = exercises[index]
        let seq = e.item.sequence
        var head = e
        head.item.exerciseId = seq[0]
        head.item.sequence = []
        let extras = seq.dropFirst().map { id -> LiveExercise in
            var item = WorkoutExercise(exerciseId: id)
            item.groupId = e.item.groupId
            return LiveExercise(item: item, defaultRest: e.restSeconds)
        }
        exercises.replaceSubrange(index...index, with: [head] + extras)
        collapseSingletons()
    }

    var incomplete: [Int] { exercises.indices.filter { exercises[$0].hasIncompleteSets } }

    mutating func skipIncomplete() { for i in incomplete.reversed() { skipExercise(i) } }
    mutating func removeIncomplete() { for i in incomplete.reversed() { removeExercise(i) } }

    /// Label per superset in order of appearance: A, B, C…
    var groupLabels: [String: String] {
        var labels: [String: String] = [:]
        for e in exercises {
            if let g = e.item.groupId, labels[g] == nil {
                labels[g] = String(Character(UnicodeScalar(UInt8(65 + labels.count % 26))))
            }
        }
        return labels
    }

    // MARK: Sets and rest

    /// Ends the running rest; the set it followed gets the actual rest time.
    mutating func closeRest(_ now: Double) {
        guard let r = rest else { return }
        let taken = max(0, Int((r.durationSec - r.remaining(now)).rounded()))
        rest = nil
        if let i = exercises.firstIndex(where: { $0.item.id == r.itemId }), exercises[i].item.sets.indices.contains(r.setIndex) {
            exercises[i].item.sets[r.setIndex].restSeconds = taken
        }
    }

    /// Keep pending.steps aligned with the combo sequence.
    mutating func ensureComboPending(measurementOf: (String) -> String) {
        for i in exercises.indices {
            let seq = exercises[i].item.sequence
            if seq.count <= 1 {
                if !exercises[i].pending.steps.isEmpty { exercises[i].pending.steps = [] }
                continue
            }
            let pending = exercises[i].pending
            let aligned = pending.steps.count == seq.count && zip(pending.steps, seq).allSatisfy { $0.exerciseId == $1 }
            let steps = aligned
                ? pending.steps
                : WorkoutSet.defaultSteps(sequence: seq, measurementOf: measurementOf, hint: exercises[i].item.sets.last ?? pending)
            var next = pending
            next.steps = steps
            next.applySteps(sequence: seq)
            if next != pending { exercises[i].pending = next }
        }
    }

    /// Logs the pending set of the current exercise. Superset: moves to the next
    /// member of the round without rest; rest starts after the round.
    mutating func logSet(_ now: Double) {
        let index = current
        guard let e = currentExercise else { return }
        closeRest(now)
        var set = e.pending
        set.restSeconds = nil
        set.applySteps(sequence: e.item.sequence)
        let setIndex = e.item.sets.count
        exercises[index].status = .active
        if exercises[index].startedAt == nil { exercises[index].startedAt = now }
        exercises[index].item.sets.append(set)
        var nextPending = set
        nextPending.notes = ""
        exercises[index].pending = nextPending
        setTimer = nil

        if let g = e.item.groupId {
            let members = exercises.indices.filter { exercises[$0].item.groupId == g && exercises[$0].isOpen }
            let done = setIndex + 1
            if let behind = members.first(where: { $0 > index && exercises[$0].item.sets.count < done }) {
                current = behind
                return
            }
            current = members.first(where: { exercises[$0].item.sets.count < exercises[$0].plannedSets }) ?? index
        }
        rest = e.restSeconds > 0
            ? LiveRest(startedAt: now, durationSec: Double(e.restSeconds), itemId: e.item.id, setIndex: setIndex)
            : nil
    }

    mutating func updateSet(_ index: Int, _ setIndex: Int, _ set: WorkoutSet) {
        guard exercises.indices.contains(index), exercises[index].item.sets.indices.contains(setIndex) else { return }
        exercises[index].item.sets[setIndex] = set
    }

    mutating func deleteSet(_ index: Int, _ setIndex: Int) {
        guard exercises.indices.contains(index), exercises[index].item.sets.indices.contains(setIndex) else { return }
        let itemId = exercises[index].item.id
        exercises[index].item.sets.remove(at: setIndex)
        guard var r = rest, r.itemId == itemId else { return }
        if r.setIndex == setIndex { rest = nil }
        else if r.setIndex > setIndex { r.setIndex -= 1; rest = r }
    }

    mutating func adjustRest(by delta: Int, _ now: Double) {
        guard var r = rest else { return }
        let remaining = r.remaining(now)
        if remaining + Double(delta) <= 0 { closeRest(now); return }
        r.durationSec += Double(delta)
        if let p = r.pausedRemaining { r.pausedRemaining = p + Double(delta) }
        r.alerted = false
        rest = r
    }

    mutating func startSetTimer(_ now: Double, target: Double?) {
        closeRest(now)
        setTimer = LiveSetTimer(startedAt: now, targetSec: target)
    }

    /// Stops the set timer and puts the time into the pending set.
    mutating func stopSetTimer(_ now: Double, field: TimerField) {
        guard let t = setTimer else { return }
        let seconds = max(1, Int(t.elapsed(now).rounded()))
        setTimer = nil
        guard exercises.indices.contains(current) else { return }
        switch field {
        case .hold: exercises[current].pending.holdSeconds = Double(seconds)
        case .duration: exercises[current].pending.durationSeconds = seconds
        }
    }

    enum TimerField { case hold, duration }

    // MARK: Summary and save

    var loggedSetCount: Int { exercises.reduce(0) { $0 + $1.item.sets.count } }

    /// The finished session as a normal workout (exercises without sets dropped).
    func workoutInput(_ now: Double) -> WorkoutInput {
        var closed = self
        closed.closeRest(now)
        var input = WorkoutInput(date: date, exercises: closed.exercises.filter { !$0.item.sets.isEmpty }.map(\.item))
        input.id = id
        input.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        input.planDayId = planDayId
        input.durationMin = max(1, Int((elapsedMs(now) / 60000).rounded()))
        input.rpe = rpe
        input.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return input
    }
}

/// Server draft envelope (`IDraft`).
struct LiveDraft: Decodable {
    let data: LiveSession
    let updatedAt: String
}

enum Clock {
    /// "4:07", "1:05:03"; negative (over time) as "+0:12".
    static func text(_ seconds: Double) -> String {
        let over = seconds < 0
        let total = Int(abs(over ? seconds.rounded(.down) : seconds.rounded(.up)))
        let body = DurationText.format(total)
        return over ? "+" + body : body
    }

    static func elapsed(_ ms: Double) -> String { text((max(0, ms) / 1000).rounded(.down)) }
}
