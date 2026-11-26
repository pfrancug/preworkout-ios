import Foundation

/// Typed endpoints. Paths mirror `server/routes/*.ts` of the web app.
extension APIClient {
    private func cacheKey(_ name: String, person: String? = nil) -> DiskCache.Key? {
        guard let userId = DiskCache.currentUserId() else { return nil }
        return DiskCache.Key(userId: userId, personId: person, name: name)
    }

    // MARK: Health + auth

    func health() async throws -> Health { try await get("/health") }
    func authSession() async throws -> AuthSession { try await get("/auth/session", cache: cacheKey("session")) }

    func logout() async throws { try await sendNoContent("POST", "/auth/logout") }

    func appleNative(
        identityToken: String,
        authorizationCode: String?,
        nonce: String?,
        fullName: String?,
        link: Bool
    ) async throws -> AppleAuthResponse {
        struct Body: Encodable {
            let identityToken: String
            let authorizationCode: String?
            let nonce: String?
            let fullName: String?
            let link: Bool
        }
        return try await send(
            "POST",
            "/auth/apple/native",
            body: Body(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                nonce: nonce,
                fullName: fullName,
                link: link
            )
        )
    }

    func deleteAccount() async throws {
        try await sendNoContent("DELETE", "/auth/account", body: ["confirm": true])
    }

    // MARK: People + profile

    func people() async throws -> [Person] { try await get("/people", cache: cacheKey("people")) }

    func personPath(_ id: String) -> String { "/people/\(seg(id))" }

    func settings(person id: String) async throws -> UserSettings {
        try await get(personPath(id) + "/settings", cache: cacheKey("settings", person: id))
    }

    func saveSettings(_ settings: UserSettings, person id: String) async throws {
        try await sendNoContent("PUT", personPath(id) + "/settings", body: settings)
        invalidate(["settings"], person: id)
    }

    func preferences() async throws -> UserPreferences { try await get("/preferences", cache: cacheKey("preferences")) }

    func categories(person id: String) async throws -> [ActivityCategory] {
        try await get(personPath(id) + "/categories", cache: cacheKey("categories", person: id))
    }

    // MARK: Nutrition goal + body weight

    func goal(person id: String) async throws -> NutritionGoal? {
        try await get(personPath(id) + "/goals", cache: cacheKey("goals", person: id))
    }

    /// Versions oldest first (the server orders by `validFrom`).
    func goalHistory(person id: String) async throws -> [NutritionGoalVersion] {
        try await get(personPath(id) + "/goals/history", cache: cacheKey("goals-history", person: id))
    }

    /// The server answers `null` when the goal was removed (all values nil).
    func saveGoal(_ goal: NutritionGoalInput, person id: String) async throws -> NutritionGoal? {
        let saved: NutritionGoal? = try await send("PUT", personPath(id) + "/goals", body: goal)
        invalidate(["goals", "goals-history"], person: id)
        return saved
    }

    func diary(person id: String) async throws -> [DiaryRow] {
        try await get(personPath(id) + "/diary", cache: cacheKey("diary", person: id))
    }

    /// Latest logged body weight (kg) and its date, from the diary.
    func latestWeight(person id: String) async throws -> (date: String, kg: Double)? {
        let rows = try await diary(person: id)
        return rows
            .filter { ($0.weight ?? 0) > 0 }
            .max { $0.date < $1.date }
            .map { (String($0.date.prefix(10)), $0.weight ?? 0) }
    }

    func upsertDiaryWeight(date: String, weight: Double, id: Int? = nil, person: String) async throws -> DiaryRow {
        struct Body: Encodable {
            var id: Int?
            var date: String
            var weight: Double
        }
        let row: DiaryRow = try await send(
            "PUT",
            personPath(person) + "/diary/entries",
            body: Body(id: (id ?? 0) > 0 ? id : nil, date: date, weight: weight)
        )
        invalidate(["diary"], person: person)
        return row
    }

    func deleteDiaryEntry(_ entryId: Int, person: String) async throws {
        try await sendNoContent("DELETE", personPath(person) + "/diary/entries/\(entryId)")
        invalidate(["diary"], person: person)
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
        try await get(personPath(id) + "/workouts", cache: cacheKey("workouts", person: id))
    }

    func workout(_ workoutId: String, person id: String) async throws -> Workout {
        try await get(personPath(id) + "/workouts/\(seg(workoutId))", cache: cacheKey("workout-\(workoutId)", person: id))
    }

    func createWorkout(_ input: WorkoutInput, person id: String) async throws -> Workout {
        let workout: Workout = try await send("POST", personPath(id) + "/workouts", body: input)
        invalidate(["workouts"], person: id)
        return workout
    }

    private func invalidate(_ names: [String], person: String? = nil) {
        for name in names {
            if let key = cacheKey(name, person: person) { DiskCache.remove(key) }
        }
    }

    func updateWorkout(_ workoutId: String, _ input: WorkoutInput, person id: String) async throws -> Workout {
        let workout: Workout = try await send("PUT", personPath(id) + "/workouts/\(seg(workoutId))", body: input)
        invalidate(["workouts", "workout-\(workoutId)"], person: id)
        return workout
    }

    func deleteWorkout(_ workoutId: String, person id: String) async throws {
        try await sendNoContent("DELETE", personPath(id) + "/workouts/\(seg(workoutId))")
        invalidate(["workouts", "workout-\(workoutId)"], person: id)
    }

    // MARK: Exercise library (shared by all people)

    func exercises() async throws -> [Exercise] { try await get("/exercises", cache: cacheKey("exercises")) }

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
        let exercise: Exercise = try await send("POST", "/exercises", body: input)
        invalidate(["exercises"])
        return exercise
    }

    func updateExercise(_ exerciseId: String, _ input: ExerciseInput) async throws -> Exercise {
        let exercise: Exercise = try await send("PUT", "/exercises/\(seg(exerciseId))", body: input)
        invalidate(["exercises"])
        return exercise
    }

    func saveAliases(_ aliases: [String], exercise exerciseId: String) async throws -> Exercise {
        let exercise: Exercise = try await send("PUT", "/exercises/\(seg(exerciseId))/aliases", body: ["aliases": aliases])
        invalidate(["exercises"])
        return exercise
    }

    /// Only unused custom exercises can be deleted (409 otherwise: archive instead).
    func deleteExercise(_ exerciseId: String) async throws {
        try await sendNoContent("DELETE", "/exercises/\(seg(exerciseId))")
        invalidate(["exercises"])
    }
}
