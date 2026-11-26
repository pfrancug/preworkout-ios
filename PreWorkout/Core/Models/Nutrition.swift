import Foundation

// Shapes mirror `shared/analytics.ts` (goals) and `shared/types.ts` (diary).

/// Saved daily goal of a person (`GET /goals`, null when not set).
struct NutritionGoal: Codable, Equatable {
    let kcal: Double?
    let protein: Double?
    let fat: Double?
    let carbs: Double?
    let updatedAt: String?

    private enum CodingKeys: String, CodingKey { case kcal, protein, fat, carbs, updatedAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kcal = c.lenientDouble(.kcal, Limits.goalKcal)
        protein = c.lenientDouble(.protein, Limits.goalMacroGrams)
        fat = c.lenientDouble(.fat, Limits.goalMacroGrams)
        carbs = c.lenientDouble(.carbs, Limits.goalMacroGrams)
        updatedAt = try? c.decodeIfPresent(String.self, forKey: .updatedAt)
    }
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

    private enum CodingKeys: String, CodingKey { case validFrom, kcal, protein, fat, carbs }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        validFrom = try c.decode(String.self, forKey: .validFrom)
        kcal = c.lenientDouble(.kcal, Limits.goalKcal)
        protein = c.lenientDouble(.protein, Limits.goalMacroGrams)
        fat = c.lenientDouble(.fat, Limits.goalMacroGrams)
        carbs = c.lenientDouble(.carbs, Limits.goalMacroGrams)
    }

    var isRemoval: Bool { kcal == nil && protein == nil && fat == nil && carbs == nil }
}

/// Origin of a diary body-weight value.
enum DiaryWeightSource: String, Codable, Hashable {
    case app
    case health
}

/// One day's diary patch when saving or importing body weight.
struct DiaryWeightPatch: Encodable {
    var id: Int?
    var date: String
    var weight: Double?
    var source: DiaryWeightSource?
    var healthWeight: Double?
    var includeWeight: Bool = true
    var includeHealthWeight: Bool = false

    private enum CodingKeys: String, CodingKey {
        case id, date, weight, source, healthWeight
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encode(date, forKey: .date)
        if includeWeight {
            try c.encode(weight, forKey: .weight)
        }
        try c.encodeIfPresent(source, forKey: .source)
        if includeHealthWeight {
            try c.encode(healthWeight, forKey: .healthWeight)
        }
    }
}

/// Diary row (only the fields the app reads). `id` is 0 when an older cache omitted it.
struct DiaryRow: Decodable, Identifiable, Hashable {
    var id: Int
    var date: String
    var weight: Double?
    var source: DiaryWeightSource
    var healthWeight: Double?

    /// Weight entered in PreWorkout, if any.
    var appWeight: Double? {
        if source == .app, let weight, weight > 0 { return weight }
        return nil
    }

    /// Weight imported from Apple Health, if any.
    var importedWeight: Double? {
        if let healthWeight, healthWeight > 0 { return healthWeight }
        if source == .health, let weight, weight > 0 { return weight }
        return nil
    }

    /// Preferred value for totals and the trend line: app, otherwise Health.
    var displayWeight: Double? {
        if let appWeight { return appWeight }
        if let importedWeight { return importedWeight }
        return weight
    }

    var hasAppWeight: Bool { (appWeight ?? 0) > 0 }
    var hasImportedWeight: Bool { (importedWeight ?? 0) > 0 }
    var hasBothWeights: Bool { hasAppWeight && hasImportedWeight }
    var hasAnyWeight: Bool { hasAppWeight || hasImportedWeight }

    private enum CodingKeys: String, CodingKey {
        case id, date, weight, source, healthWeight
    }

    init(
        id: Int,
        date: String,
        weight: Double?,
        source: DiaryWeightSource = .app,
        healthWeight: Double? = nil
    ) {
        self.id = id
        self.date = date
        self.weight = weight
        self.source = source
        self.healthWeight = healthWeight
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
        date = try c.decode(String.self, forKey: .date)
        weight = c.lenientDouble(.weight, Limits.bodyWeightKg)
        source = (try? c.decodeIfPresent(DiaryWeightSource.self, forKey: .source)) ?? .app
        healthWeight = c.lenientDouble(.healthWeight, Limits.bodyWeightKg)
    }
}
