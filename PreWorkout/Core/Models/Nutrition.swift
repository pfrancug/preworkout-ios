import Foundation

// Shapes mirror `shared/analytics.ts` (goals) and `shared/types.ts` (diary).

/// Saved daily goal of a person (`GET /goals`, null when not set).
struct NutritionGoal: Codable, Equatable {
    let kcal: Double?
    let protein: Double?
    let fat: Double?
    let carbs: Double?
    let updatedAt: String?
}

/// Body of `PUT /goals`; every key is required, nil is sent as `null` (= not set).
struct NutritionGoalInput: Encodable, Equatable {
    var kcal: Double?
    var protein: Double?
    var fat: Double?
    var carbs: Double?

    private enum CodingKeys: String, CodingKey { case kcal, protein, fat, carbs }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kcal, forKey: .kcal)
        try c.encode(protein, forKey: .protein)
        try c.encode(fat, forKey: .fat)
        try c.encode(carbs, forKey: .carbs)
    }
}

/// One saved version of the goal; all values nil = goal removed from that date.
struct NutritionGoalVersion: Codable, Identifiable, Hashable {
    var id: String { validFrom }
    /// YYYY-MM-DD
    let validFrom: String
    let kcal: Double?
    let protein: Double?
    let fat: Double?
    let carbs: Double?

    var isRemoval: Bool { kcal == nil && protein == nil && fat == nil && carbs == nil }
}

/// Diary row (only the fields the app reads). `id` is 0 when an older cache omitted it.
struct DiaryRow: Decodable, Identifiable, Hashable {
    var id: Int
    var date: String
    var weight: Double?

    private enum CodingKeys: String, CodingKey { case id, date, weight }

    init(id: Int, date: String, weight: Double?) {
        self.id = id
        self.date = date
        self.weight = weight
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
        date = try c.decode(String.self, forKey: .date)
        weight = try c.decodeIfPresent(Double.self, forKey: .weight)
    }
}
