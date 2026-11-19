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

    // MARK: Workouts

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
