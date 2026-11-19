import Foundation

// Shapes mirror `shared/training.ts` of the web app.

struct ExerciseRef: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
}

struct Exercise: Decodable, Identifiable {
    let id: String
    let name: String
    let aliases: [String]?
    /// calisthenics | gym | cardio | mobility | other
    let modality: String
    /// push | pull | legs | core | skill | mobility | explosive
    let category: String
    let muscles: [String]
    let musclesPrimary: [String]?
    let equipment: [String]
    let difficulty: String?
    /// reps | hold | reps_weight | distance_time
    let measurement: String
    let description: String
    let variants: [String]
    let isCustom: Bool
    let archived: Bool
}

struct TrainingPlanSummary: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let goal: String
    let startDate: String?
    let endDate: String?
    let weeks: Int?
    let isActive: Bool
    let dayCount: Int
    let updatedAt: String
}

struct PlanExercise: Codable, Identifiable, Hashable {
    let id: String
    var exerciseId: String
    var variant: String?
    var targetSets: Int?
    var targetRepsMin: Int?
    var targetRepsMax: Int?
    var targetHoldMin: Double?
    var targetHoldMax: Double?
    var targetWeightKg: Double?
    var targetRpe: Double?
    var restSeconds: Int?
    var progressionTarget: String
    var notes: String
}

struct PlanDay: Codable, Identifiable, Hashable {
    let id: String
    var week: Int?
    var name: String
    var notes: String
    var exercises: [PlanExercise]
}

struct TrainingPlan: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var goal: String
    var notes: String
    var startDate: String?
    var endDate: String?
    var weeks: Int?
    var isActive: Bool
    var days: [PlanDay]
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

    enum CodingKeys: String, CodingKey {
        case isWarmup, reps, holdSeconds, weightKg, distanceM, durationSeconds
        case assistance, assistanceNote, rpe, rir, restSeconds, notes
    }
}

struct WorkoutExercise: Codable, Identifiable, Hashable {
    let id: String
    var exerciseId: String
    var planExerciseId: String?
    var variant: String?
    var notes: String = ""
    /// Same id = superset / pair
    var groupId: String?
    /// Exercise ids done in order as one set (combo); [] = single exercise
    var sequence: [String] = []
    var sets: [WorkoutSet]

    enum CodingKeys: String, CodingKey {
        case id, exerciseId, planExerciseId, variant, notes, groupId, sequence, sets
    }
}

/// Body of POST/PUT `/workouts` (`workoutInputSchema`).
struct WorkoutInput: Encodable {
    /// Client-generated id so a retried save does not duplicate the workout.
    var id: String = UUID().uuidString.lowercased()
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

    // Optionals must be sent as explicit `null` (the zod schema requires the keys).
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

    private enum CodingKeys: String, CodingKey {
        case id, date, title, categoryId, calendarEntryId, planDayId, durationMin, rpe, notes, exercises
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
    let createdAt: String
    let updatedAt: String
}

struct WorkoutSummary: Decodable, Identifiable, Hashable {
    let id: String
    let date: String
    let title: String
    let categoryId: String?
    let calendarEntryId: String?
    let planDayId: String?
    let planDayName: String?
    let planName: String?
    let durationMin: Int?
    let rpe: Double?
    let exerciseCount: Int
    let setCount: Int
    let exerciseNames: [String]
    let exerciseIds: [String]
    let setNotes: [String]
}

// The API's zod schemas require nullable keys to be present, so optionals are
// encoded as explicit `null` instead of being omitted.

extension WorkoutSet {
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
    }
}

extension WorkoutExercise {
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(exerciseId, forKey: .exerciseId)
        try c.encode(planExerciseId, forKey: .planExerciseId)
        try c.encode(variant, forKey: .variant)
        try c.encode(notes, forKey: .notes)
        try c.encode(groupId, forKey: .groupId)
        try c.encode(sequence, forKey: .sequence)
        try c.encode(sets, forKey: .sets)
    }
}
