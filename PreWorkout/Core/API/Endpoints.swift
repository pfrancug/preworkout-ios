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

    private func person(_ id: String) -> String { "/people/\(seg(id))" }

    func settings(person id: String) async throws -> UserSettings {
        try await get(person(id) + "/settings")
    }

    func saveSettings(_ settings: UserSettings, person id: String) async throws {
        try await sendNoContent("PUT", person(id) + "/settings", body: settings)
    }

    func preferences() async throws -> UserPreferences { try await get("/preferences") }

    // MARK: Diary (weight + macros)

    func diary(person id: String) async throws -> [DiaryRow] { try await get(person(id) + "/diary") }

    /// NOTE: the current API only replaces the whole diary (PUT). A per-row
    /// endpoint is planned on the backend before the app edits the diary.
    func replaceDiary(_ rows: [DiaryRow], person id: String) async throws {
        try await sendNoContent("PUT", person(id) + "/diary", body: rows)
    }

    // MARK: Calendar

    func categories(person id: String) async throws -> [ActivityCategory] {
        try await get(person(id) + "/categories")
    }

    func calendarEntries(person id: String) async throws -> CalendarEntries {
        try await get(person(id) + "/calendar/entries")
    }

    func calendarNotes(person id: String) async throws -> [String: String] {
        try await get(person(id) + "/calendar/notes")
    }

    // MARK: Training

    func plans(person id: String) async throws -> [TrainingPlanSummary] {
        try await get(person(id) + "/plans")
    }

    func plan(_ planId: String, person id: String) async throws -> TrainingPlan {
        try await get(person(id) + "/plans/\(seg(planId))")
    }

    func workouts(person id: String, from: String? = nil, to: String? = nil) async throws -> [WorkoutSummary] {
        var query: [String] = []
        if let from { query.append("from=\(from)") }
        if let to { query.append("to=\(to)") }
        return try await get(person(id) + "/workouts" + (query.isEmpty ? "" : "?" + query.joined(separator: "&")))
    }

    func workout(_ workoutId: String, person id: String) async throws -> Workout {
        try await get(person(id) + "/workouts/\(seg(workoutId))")
    }

    func createWorkout(_ input: WorkoutInput, person id: String) async throws -> Workout {
        try await send("POST", person(id) + "/workouts", body: input)
    }

    // MARK: Exercise library (shared by all people)

    func searchExercises(_ query: String, limit: Int = 50) async throws -> [ExerciseRef] {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return try await get("/exercises/search?q=\(q)&limit=\(limit)")
    }

    func exercise(_ exerciseId: String) async throws -> Exercise {
        try await get("/exercises/\(seg(exerciseId))")
    }

    // MARK: Analytics + goals

    func analyticsSummary(person id: String, days: Int) async throws -> AnalyticsSummary {
        try await get(person(id) + "/analytics/summary?days=\(days)")
    }

    func goal(person id: String) async throws -> NutritionGoal? {
        try await get(person(id) + "/goals")
    }

    func saveGoal(_ goal: NutritionGoalInput, person id: String) async throws -> NutritionGoal {
        try await send("PUT", person(id) + "/goals", body: goal)
    }
}
