import Foundation

// Shapes mirror `shared/types.ts` of the web app (JSON is camelCase).

struct Health: Decodable {
    let ok: Bool
    let ai: Bool
}

struct AuthSession: Decodable {
    let required: Bool
    let authenticated: Bool
}

struct UserSettings: Codable, Equatable {
    var name: String
    var age: String
    var height: String
    /// "male" | "female" | ""
    var sex: String
    var avatarUrl: String?
}

struct Person: Decodable, Identifiable, Hashable {
    static let ownerId = "owner"

    let id: String
    let isOwner: Bool
    let createdAt: String
    let name: String
    let age: String
    let height: String
    let sex: String
    let avatarUrl: String?

    var displayName: String { name.isEmpty ? (isOwner ? "Ja" : id) : name }
}

struct UserPreferences: Decodable {
    let language: String?
    let defaultCalendarView: String?
}

/// Diary row (one day): weight + nutrition.
struct DiaryRow: Codable, Identifiable, Hashable {
    let id: Int
    /// YYYY-MM-DD
    var date: String
    var weight: Double?
    var kcal: Double?
    var protein: Double?
    var fat: Double?
    var carbs: Double?
    var completed: Bool?
}

struct ActivityCategory: Codable, Identifiable, Hashable {
    let id: String
    var icon: String
    var name: String
    var color: String
    var archived: Bool?
}

struct CalendarEntry: Codable, Identifiable, Hashable {
    let id: String
    /// "activity" | "custom"
    let type: String
    let activityId: String?
    let name: String?
    let icon: String?
    let color: String?
    /// HH:mm, nil = all day
    let time: String?
    let timeEnd: String?
    let note: String?
}

/// date (YYYY-MM-DD) -> entry id -> entry
typealias CalendarEntries = [String: [String: CalendarEntry]]

struct NutritionGoalInput: Encodable, Equatable {
    var kcal: Double?
    var protein: Double?
    var fat: Double?
    var carbs: Double?

    private enum CodingKeys: String, CodingKey { case kcal, protein, fat, carbs }

    // The API requires every key; nil is sent as `null` (= not set).
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kcal, forKey: .kcal)
        try c.encode(protein, forKey: .protein)
        try c.encode(fat, forKey: .fat)
        try c.encode(carbs, forKey: .carbs)
    }
}

struct NutritionGoal: Decodable {
    let kcal: Double?
    let protein: Double?
    let fat: Double?
    let carbs: Double?
    let updatedAt: String?
}
