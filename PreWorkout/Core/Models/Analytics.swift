import Foundation

// Subset of `shared/analytics.ts` used by the dashboard.

struct DateRange: Decodable, Hashable {
    let from: String
    let to: String
    let days: Int
}

struct WeightTrend: Decodable {
    struct Latest: Decodable { let date: String; let weight: Double }
    let entries: Int
    let latest: Latest?
    let avg7: Double?
    let avgPrev7: Double?
    let ratePerWeek: Double?
    let change: Double?
    let min: Double?
    let max: Double?
}

struct MacroAverages: Decodable {
    let kcal: Double?
    let protein: Double?
    let fat: Double?
    let carbs: Double?
}

struct NutritionSummary: Decodable {
    let loggedDays: Int
    let adherencePct: Double
    let avg: MacroAverages
    let proteinPerKg: Double?
    let completedDays: Int
    let withinGoalPct: MacroAverages
}

struct TrainingSummary: Decodable {
    let activities: Int
    let activitiesPerWeek: Double
    let workouts: Int
    let workoutMinutes: Double
    let avgWorkoutRpe: Double?
    let trainingDays: Int
    let longestGapDays: Int
    let lastTrainingDate: String?
}

struct AnalyticsSummary: Decodable {
    let range: DateRange
    let weight: WeightTrend
    let nutrition: NutritionSummary
    let training: TrainingSummary
}
