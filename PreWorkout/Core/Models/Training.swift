import Foundation

// Shapes mirror `shared/training.ts` of the web app. The API's zod schemas
// require nullable keys to be present, so request bodies encode optionals as
// explicit `null` instead of omitting them.

struct ExerciseRef: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
}

struct ExerciseLink: Codable, Hashable {
    let source: String
    let type: String
    let url: String
    let license: String?
}

struct Exercise: Decodable, Identifiable, Hashable {
    let id: String
    var name: String
    var aliases: [String]
    /// calisthenics | gym | cardio | mobility | other
    var modality: String
    /// push | pull | legs | core | skill | mobility | explosive
    var category: String
    var muscles: [String]
    var musclesPrimary: [String]
    var equipment: [String]
    var family: String?
    /// beginner | intermediate | advanced | elite
    var difficulty: String?
    /// reps | hold | reps_weight | distance_time
    var measurement: String
    var description: String
    var variants: [String]
    var prevExerciseId: String?
    var nextExerciseId: String?
    var source: String?
    var sourceLicense: String?
    var sourceUrl: String?
    var links: [ExerciseLink]
    var isCustom: Bool
    var archived: Bool

    private enum CodingKeys: String, CodingKey {
        case id, name, aliases, modality, category, muscles, musclesPrimary, equipment, family
        case difficulty, measurement, description, variants, prevExerciseId, nextExerciseId
        case source, sourceLicense, sourceUrl, links, isCustom, archived
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        modality = try c.decodeIfPresent(String.self, forKey: .modality) ?? "other"
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? "skill"
        muscles = try c.decodeIfPresent([String].self, forKey: .muscles) ?? []
        musclesPrimary = try c.decodeIfPresent([String].self, forKey: .musclesPrimary) ?? []
        equipment = try c.decodeIfPresent([String].self, forKey: .equipment) ?? []
        family = try c.decodeIfPresent(String.self, forKey: .family)
        difficulty = try c.decodeIfPresent(String.self, forKey: .difficulty)
        measurement = try c.decodeIfPresent(String.self, forKey: .measurement) ?? "reps"
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        variants = try c.decodeIfPresent([String].self, forKey: .variants) ?? []
        prevExerciseId = try c.decodeIfPresent(String.self, forKey: .prevExerciseId)
        nextExerciseId = try c.decodeIfPresent(String.self, forKey: .nextExerciseId)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        sourceLicense = try c.decodeIfPresent(String.self, forKey: .sourceLicense)
        sourceUrl = try c.decodeIfPresent(String.self, forKey: .sourceUrl)
        links = (try? c.decodeIfPresent([ExerciseLink].self, forKey: .links)) ?? []
        isCustom = try c.decodeIfPresent(Bool.self, forKey: .isCustom) ?? false
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
    }

    /// Muscles that are not primary (secondary).
    var musclesSecondary: [String] {
        musclesPrimary.isEmpty ? [] : muscles.filter { !musclesPrimary.contains($0) }
    }
}

/// Body of POST/PUT `/exercises` (`exerciseInputSchema`).
struct ExerciseInput: Encodable, Equatable {
    var name = ""
    var modality = "calisthenics"
    var category = "push"
    var muscles: [String] = []
    var musclesPrimary: [String] = []
    var equipment: [String] = []
    var family: String?
    var difficulty: String?
    var measurement = "reps"
    var description = ""
    var variants: [String] = []
    var prevExerciseId: String?
    var nextExerciseId: String?
    var archived = false

    init() {}

    init(_ e: Exercise) {
        name = e.name
        modality = e.modality
        category = e.category
        muscles = e.muscles
        musclesPrimary = e.musclesPrimary
        equipment = e.equipment
        family = e.family
        difficulty = e.difficulty
        measurement = e.measurement
        description = e.description
        variants = e.variants
        prevExerciseId = e.prevExerciseId
        nextExerciseId = e.nextExerciseId
        archived = e.archived
    }

    private enum CodingKeys: String, CodingKey {
        case name, modality, category, muscles, musclesPrimary, equipment, family, difficulty
        case measurement, description, variants, prevExerciseId, nextExerciseId, archived
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(modality, forKey: .modality)
        try c.encode(category, forKey: .category)
        try c.encode(muscles, forKey: .muscles)
        try c.encode(musclesPrimary, forKey: .musclesPrimary)
        try c.encode(equipment, forKey: .equipment)
        try c.encode(family, forKey: .family)
        try c.encode(difficulty, forKey: .difficulty)
        try c.encode(measurement, forKey: .measurement)
        try c.encode(description, forKey: .description)
        try c.encode(variants, forKey: .variants)
        try c.encode(prevExerciseId, forKey: .prevExerciseId)
        try c.encode(nextExerciseId, forKey: .nextExerciseId)
        try c.encode(archived, forKey: .archived)
    }
}

// MARK: Workouts

/// Per-movement values inside a combo set; [] = single-value / legacy set.
struct WorkoutSetStep: Codable, Hashable {
    var exerciseId: String
    var reps: Int? = nil
    var holdSeconds: Double? = nil
    var durationSeconds: Int? = nil

    private enum CodingKeys: String, CodingKey {
        case exerciseId, reps, holdSeconds, durationSeconds
    }

    var hasValue: Bool { reps != nil || holdSeconds != nil || durationSeconds != nil }

    var valueText: String {
        if let reps { return String(reps) }
        if let holdSeconds { return DurationText.format(holdSeconds) }
        if let durationSeconds { return DurationText.format(durationSeconds) }
        return "–"
    }

    init(exerciseId: String, reps: Int? = nil, holdSeconds: Double? = nil, durationSeconds: Int? = nil) {
        self.exerciseId = exerciseId
        self.reps = reps
        self.holdSeconds = holdSeconds
        self.durationSeconds = durationSeconds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        exerciseId = try c.decode(String.self, forKey: .exerciseId)
        reps = c.lenientInt(.reps, Limits.reps)
        holdSeconds = c.lenientDouble(.holdSeconds, Limits.durationSeconds)
        durationSeconds = c.lenientInt(.durationSeconds, Limits.durationSeconds)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(exerciseId, forKey: .exerciseId)
        try c.encode(reps, forKey: .reps)
        try c.encode(holdSeconds, forKey: .holdSeconds)
        try c.encode(durationSeconds, forKey: .durationSeconds)
    }
}

struct WorkoutSet: Codable, Hashable {
    var isWarmup: Bool = false
    var reps: Int?
    var holdSeconds: Double?
    var weightKg: Double?
    var distanceM: Double?
    var durationSeconds: Int?
    /// none | band | partner | other
    var assistance: String = "none"
    var assistanceNote: String = ""
    var rpe: Double?
    var rir: Int?
    var restSeconds: Int?
    var notes: String = ""
    /// Optional attempt count for a session/block.
    var attempts: Int? = nil
    /// Per-step reps/duration for a combo; omitted or [] on older payloads.
    var steps: [WorkoutSetStep] = []

    private enum CodingKeys: String, CodingKey {
        case isWarmup, reps, holdSeconds, weightKg, distanceM, durationSeconds
        case assistance, assistanceNote, rpe, rir, restSeconds, notes, attempts, steps
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isWarmup = try c.decodeIfPresent(Bool.self, forKey: .isWarmup) ?? false
        reps = c.lenientInt(.reps, Limits.reps)
        holdSeconds = c.lenientDouble(.holdSeconds, Limits.durationSeconds)
        weightKg = c.lenientDouble(.weightKg, Limits.loadKg)
        distanceM = c.lenientDouble(.distanceM, Limits.distanceM)
        durationSeconds = c.lenientInt(.durationSeconds, Limits.durationSeconds)
        assistance = try c.decodeIfPresent(String.self, forKey: .assistance) ?? "none"
        assistanceNote = try c.decodeIfPresent(String.self, forKey: .assistanceNote) ?? ""
        rpe = c.lenientDouble(.rpe, Limits.rpe)
        rir = c.lenientInt(.rir, Limits.rir)
        restSeconds = c.lenientInt(.restSeconds, Limits.restSeconds)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        attempts = c.lenientInt(.attempts, Limits.attempts)
        steps = try c.decodeIfPresent([WorkoutSetStep].self, forKey: .steps) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(isWarmup, forKey: .isWarmup)
        try c.encode(reps, forKey: .reps)
        try c.encode(holdSeconds, forKey: .holdSeconds)
        try c.encode(weightKg, forKey: .weightKg)
        try c.encode(distanceM, forKey: .distanceM)
        try c.encode(durationSeconds, forKey: .durationSeconds)
        try c.encode(assistance, forKey: .assistance)
        try c.encode(assistanceNote, forKey: .assistanceNote)
        try c.encode(rpe, forKey: .rpe)
        try c.encode(rir, forKey: .rir)
        try c.encode(restSeconds, forKey: .restSeconds)
        try c.encode(notes, forKey: .notes)
        try c.encodeIfPresent(attempts, forKey: .attempts)
        try c.encode(steps, forKey: .steps)
    }

    /// "1 / 5 / 1" when steps exist.
    var stepsSummary: String? {
        steps.isEmpty ? nil : steps.map(\.valueText).joined(separator: " / ")
    }

    /// Align steps to the combo sequence and copy the last step onto top-level fields.
    mutating func applySteps(sequence: [String]) {
        guard sequence.count > 1 else {
            steps = []
            return
        }
        guard !steps.isEmpty else { return }
        steps = sequence.enumerated().map { index, id in
            let byIndex = steps[safe: index]
            let source = byIndex?.exerciseId == id ? byIndex : (steps.first { $0.exerciseId == id } ?? byIndex)
            return WorkoutSetStep(
                exerciseId: id,
                reps: source?.reps,
                holdSeconds: source?.holdSeconds,
                durationSeconds: source?.durationSeconds
            )
        }
        if let last = steps.last {
            reps = last.reps
            holdSeconds = last.holdSeconds
            durationSeconds = last.durationSeconds
        }
    }

    static func defaultSteps(
        sequence: [String],
        measurementOf: (String) -> String,
        hint: WorkoutSet?
    ) -> [WorkoutSetStep] {
        guard sequence.count > 1 else { return [] }
        if let hint, !hint.steps.isEmpty {
            var aligned = hint
            aligned.applySteps(sequence: sequence)
            return sequence.enumerated().map { index, id in
                let existing = aligned.steps[safe: index]
                if let existing, existing.hasValue { return existing }
                return defaultStep(id, measurementOf(id), hint: existing)
            }
        }
        return sequence.enumerated().map { index, id in
            defaultStep(id, measurementOf(id), hint: index == sequence.count - 1 ? hint : Optional<WorkoutSet>.none)
        }
    }

    static func defaultStep(_ exerciseId: String, _ measurement: String, hint: WorkoutSetStep? = nil) -> WorkoutSetStep {
        switch measurement {
        case "hold":
            return WorkoutSetStep(exerciseId: exerciseId, holdSeconds: hint?.holdSeconds ?? 1)
        case "distance_time":
            return WorkoutSetStep(exerciseId: exerciseId, durationSeconds: hint?.durationSeconds ?? 1)
        default:
            return WorkoutSetStep(exerciseId: exerciseId, reps: hint?.reps ?? 1)
        }
    }

    static func defaultStep(_ exerciseId: String, _ measurement: String, hint: WorkoutSet?) -> WorkoutSetStep {
        switch measurement {
        case "hold":
            return WorkoutSetStep(exerciseId: exerciseId, holdSeconds: hint?.holdSeconds ?? 1)
        case "distance_time":
            return WorkoutSetStep(exerciseId: exerciseId, durationSeconds: hint?.durationSeconds ?? 1)
        default:
            return WorkoutSetStep(exerciseId: exerciseId, reps: hint?.reps ?? 1)
        }
    }
}

struct WorkoutExercise: Codable, Identifiable, Hashable {
    var id: String = newId()
    var exerciseId: String
    var planExerciseId: String?
    var variant: String?
    var notes: String = ""
    /// Same id = superset / pair
    var groupId: String?
    /// Exercise ids done in order as one set (combo); [] = single exercise
    var sequence: [String] = []
    /// "sets" (default) or "session" (one timed block).
    var kind: String = "sets"
    var sets: [WorkoutSet] = []
    var isSession: Bool { kind == "session" }

    private enum CodingKeys: String, CodingKey {
        case id, exerciseId, planExerciseId, variant, notes, groupId, sequence, kind, sets
    }

    init(exerciseId: String) { self.exerciseId = exerciseId }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        exerciseId = try c.decode(String.self, forKey: .exerciseId)
        planExerciseId = try c.decodeIfPresent(String.self, forKey: .planExerciseId)
        variant = try c.decodeIfPresent(String.self, forKey: .variant)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        groupId = try c.decodeIfPresent(String.self, forKey: .groupId)
        sequence = try c.decodeIfPresent([String].self, forKey: .sequence) ?? []
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "sets"
        sets = try c.decodeIfPresent([WorkoutSet].self, forKey: .sets) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(exerciseId, forKey: .exerciseId)
        try c.encode(planExerciseId, forKey: .planExerciseId)
        try c.encode(variant, forKey: .variant)
        try c.encode(notes, forKey: .notes)
        try c.encode(groupId, forKey: .groupId)
        try c.encode(sequence, forKey: .sequence)
        try c.encode(kind, forKey: .kind)
        try c.encode(sets, forKey: .sets)
    }
}

/// Body of POST/PUT `/workouts` (`workoutInputSchema`).
struct WorkoutInput: Encodable {
    /// Client-generated id so a retried save does not duplicate the workout.
    var id: String = newId()
    /// YYYY-MM-DD
    var date: String
    var title: String = ""
    var categoryId: String?
    var calendarEntryId: String?
    var planDayId: String?
    var durationMin: Int?
    var rpe: Double?
    var notes: String = ""
    var exercises: [WorkoutExercise]

    private enum CodingKeys: String, CodingKey {
        case id, date, title, categoryId, calendarEntryId, planDayId, durationMin, rpe, notes, exercises
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(date, forKey: .date)
        try c.encode(title, forKey: .title)
        try c.encode(categoryId, forKey: .categoryId)
        try c.encode(calendarEntryId, forKey: .calendarEntryId)
        try c.encode(planDayId, forKey: .planDayId)
        try c.encode(durationMin, forKey: .durationMin)
        try c.encode(rpe, forKey: .rpe)
        try c.encode(notes, forKey: .notes)
        try c.encode(exercises, forKey: .exercises)
    }
}

struct Workout: Decodable, Identifiable, Hashable {
    let id: String
    let date: String
    let title: String
    let categoryId: String?
    let calendarEntryId: String?
    let planDayId: String?
    let durationMin: Int?
    let rpe: Double?
    let notes: String
    let exercises: [WorkoutExercise]
}

extension Workout {
    /// The workout as it was saved offline (what the server will return for this input).
    init(_ input: WorkoutInput) {
        self.init(
            id: input.id, date: input.date, title: input.title, categoryId: input.categoryId,
            calendarEntryId: input.calendarEntryId, planDayId: input.planDayId,
            durationMin: input.durationMin, rpe: input.rpe, notes: input.notes, exercises: input.exercises
        )
    }
}

struct WorkoutSummary: Decodable, Identifiable, Hashable {
    let id: String
    let date: String
    let title: String
    let categoryId: String?
    /// Calendar activity this workout was started from (shown once, as the workout).
    let calendarEntryId: String?
    let planDayId: String?
    let planDayName: String?
    let planName: String?
    let durationMin: Int?
    let rpe: Double?
    let exerciseCount: Int
    let setCount: Int
    let exerciseNames: [String]
}

/// Lowercase UUID used for client-generated ids (max 64 chars on the API).
func newId() -> String { UUID().uuidString.lowercased() }
