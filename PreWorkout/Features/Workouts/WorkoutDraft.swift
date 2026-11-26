import Foundation

/// Editable copy of a workout. Sets get a local identity so SwiftUI lists can
/// add / delete them safely.
struct DraftSet: Identifiable, Hashable {
    let id = UUID()
    var value: WorkoutSet
}

struct DraftExercise: Identifiable, Hashable {
    var id: String = newId()
    var exerciseId: String
    var planExerciseId: String?
    var variant: String?
    var notes = ""
    var groupId: String?
    var sequence: [String] = []
    var kind: String = "sets"
    var sets: [DraftSet] = []

    var isSession: Bool { kind == "session" }

    init(exerciseId: String, sets: [WorkoutSet] = [WorkoutSet()]) {
        self.exerciseId = exerciseId
        self.sets = sets.map { DraftSet(value: $0) }
    }

    init(_ e: WorkoutExercise) {
        id = e.id
        exerciseId = e.exerciseId
        planExerciseId = e.planExerciseId
        variant = e.variant
        notes = e.notes
        groupId = e.groupId
        sequence = e.sequence
        kind = e.kind
        sets = e.sets.map { DraftSet(value: $0) }
    }

    var output: WorkoutExercise {
        var e = WorkoutExercise(exerciseId: exerciseId)
        e.id = id
        e.planExerciseId = planExerciseId
        e.variant = variant
        e.notes = notes
        e.groupId = groupId
        e.sequence = sequence
        e.kind = kind
        e.sets = isSession ? [sets.first?.value ?? WorkoutSet()] : sets.map(\.value)
        return e
    }
}

struct WorkoutDraft: Hashable {
    var date = Date()
    var title = ""
    var categoryId: String?
    var calendarEntryId: String?
    var planDayId: String?
    var durationMin: Int?
    var rpe: Double?
    var notes = ""
    var exercises: [DraftExercise] = []

    init() {}

    init(_ w: Workout) {
        date = DayString.date(from: w.date) ?? Date()
        title = w.title
        categoryId = w.categoryId
        calendarEntryId = w.calendarEntryId
        planDayId = w.planDayId
        durationMin = w.durationMin
        rpe = w.rpe
        notes = w.notes
        exercises = w.exercises.map(DraftExercise.init)
    }

    func input(id: String?) -> WorkoutInput {
        var input = WorkoutInput(date: DayString.string(from: date), exercises: exercises.map(\.output))
        if let id { input.id = id }
        input.title = title.trimmingCharacters(in: .whitespaces)
        input.categoryId = categoryId
        input.calendarEntryId = calendarEntryId
        input.planDayId = planDayId
        input.durationMin = durationMin
        input.rpe = rpe
        input.notes = notes
        return input
    }

    /// Localized validation error, nil when the API will accept it.
    var validationError: String? {
        if let rpe, !Limits.rpe.contains(rpe) { return Limits.rpe.message }
        if let durationMin, !Limits.sessionMinutes.contains(Double(durationMin)) { return Limits.sessionMinutes.message }
        for exercise in exercises {
            if exercise.sets.count > 50 { return String(localized: "Ćwiczenie może mieć najwyżej 50 serii.") }
            for set in exercise.sets.map(\.value) {
                if let rpe = set.rpe, !Limits.rpe.contains(rpe) { return Limits.rpe.message }
                if let rir = set.rir, !Limits.rir.contains(Double(rir)) { return Limits.rir.message }
                if let reps = set.reps, !Limits.reps.contains(Double(reps)) { return Limits.reps.message }
                if let attempts = set.attempts, !Limits.attempts.contains(Double(attempts)) { return Limits.attempts.message }
                if let weight = set.weightKg, !Limits.loadKg.contains(weight) { return Limits.loadKg.message }
                if let distance = set.distanceM, !Limits.distanceM.contains(distance) { return Limits.distanceM.message }
                if let hold = set.holdSeconds, !Limits.durationSeconds.contains(hold) { return Limits.durationSeconds.message }
                if let duration = set.durationSeconds, !Limits.durationSeconds.contains(Double(duration)) { return Limits.durationSeconds.message }
                if let rest = set.restSeconds, !Limits.restSeconds.contains(Double(rest)) { return Limits.restSeconds.message }
            }
        }
        return nil
    }
}
