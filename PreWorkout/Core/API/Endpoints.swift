import Foundation

/// Typed endpoints. Paths mirror `server/routes/*.ts` of the web app.
extension APIClient {
    // MARK: Health + auth

    func health() async throws -> Health { try await get("/health") }
    func authSession() async throws -> AuthSession { try await get("/auth/session") }

    func login(password: String) async throws {
        try await sendNoContent("POST", "/auth/login", body: ["password": password])
    }

    func logout() async throws { try await sendNoContent("POST", "/auth/logout") }

    // MARK: People + profile

    func people() async throws -> [Person] { try await get("/people") }

    func personPath(_ id: String) -> String { "/people/\(seg(id))" }

    func settings(person id: String) async throws -> UserSettings {
        try await get(personPath(id) + "/settings")
    }

    func saveSettings(_ settings: UserSettings, person id: String) async throws {
        try await sendNoContent("PUT", personPath(id) + "/settings", body: settings)
    }

    func preferences() async throws -> UserPreferences { try await get("/preferences") }

    func categories(person id: String) async throws -> [ActivityCategory] {
        try await get(personPath(id) + "/categories")
    }

    // MARK: Nutrition goal + body weight

    func goal(person id: String) async throws -> NutritionGoal? {
        try await get(personPath(id) + "/goals")
    }

    /// Versions oldest first (the server orders by `validFrom`).
    func goalHistory(person id: String) async throws -> [NutritionGoalVersion] {
        try await get(personPath(id) + "/goals/history")
    }

    func saveGoal(_ goal: NutritionGoalInput, person id: String) async throws -> NutritionGoal {
        try await send("PUT", personPath(id) + "/goals", body: goal)
    }

    /// Latest logged body weight (kg) and its date, from the diary.
    func latestWeight(person id: String) async throws -> (date: String, kg: Double)? {
        let rows: [DiaryRow] = try await get(personPath(id) + "/diary")
        return rows
            .filter { ($0.weight ?? 0) > 0 }
            .max { $0.date < $1.date }
            .map { (String($0.date.prefix(10)), $0.weight ?? 0) }
    }

    // MARK: Workouts

    /// Live workout left in the server drafts table (`workout` / `live-session`); nil when none or unreadable.
    func liveDraft(person id: String) async throws -> LiveDraft? {
        try await get(personPath(id) + "/drafts/workout/" + LiveSession.draftKey)
    }

    func deleteLiveDraft(person id: String) async throws {
        try await sendNoContent("DELETE", personPath(id) + "/drafts/workout/" + LiveSession.draftKey)
    }

    func workouts(person id: String) async throws -> [WorkoutSummary] {
        try await get(personPath(id) + "/workouts")
    }

    func workout(_ workoutId: String, person id: String) async throws -> Workout {
        try await get(personPath(id) + "/workouts/\(seg(workoutId))")
    }

    func createWorkout(_ input: WorkoutInput, person id: String) async throws -> Workout {
        try await send("POST", personPath(id) + "/workouts", body: input)
    }

    func updateWorkout(_ workoutId: String, _ input: WorkoutInput, person id: String) async throws -> Workout {
        try await send("PUT", personPath(id) + "/workouts/\(seg(workoutId))", body: input)
    }

    func deleteWorkout(_ workoutId: String, person id: String) async throws {
        try await sendNoContent("DELETE", personPath(id) + "/workouts/\(seg(workoutId))")
    }

    // MARK: Exercise library (shared by all people)

    func exercises() async throws -> [Exercise] { try await get("/exercises") }

    /// Full-text search (names, aliases, diacritics, typos), best match first.
    func searchExercises(_ query: String, limit: Int = 60) async throws -> [ExerciseRef] {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        let q = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return try await get("/exercises/search?q=\(q)&limit=\(limit)")
    }

    func exercise(_ exerciseId: String) async throws -> Exercise {
        try await get("/exercises/\(seg(exerciseId))")
    }

    func createExercise(_ input: ExerciseInput) async throws -> Exercise {
        try await send("POST", "/exercises", body: input)
    }

    func updateExercise(_ exerciseId: String, _ input: ExerciseInput) async throws -> Exercise {
        try await send("PUT", "/exercises/\(seg(exerciseId))", body: input)
    }

    func saveAliases(_ aliases: [String], exercise exerciseId: String) async throws -> Exercise {
        try await send("PUT", "/exercises/\(seg(exerciseId))/aliases", body: ["aliases": aliases])
    }

    /// Only unused custom exercises can be deleted (409 otherwise: archive instead).
    func deleteExercise(_ exerciseId: String) async throws {
        try await sendNoContent("DELETE", "/exercises/\(seg(exerciseId))")
    }
}
