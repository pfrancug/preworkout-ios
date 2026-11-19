import Foundation

/// Mifflin-St Jeor calculator; same constants and rounding as the web app
/// (`src/pages/Calculator`, `src/constants/storage.ts`, `src/lib/goals.ts`).
enum Calculator {
    static let defaultAge = 30
    static let defaultHeight = 175
    static let defaultWeight = 75.0
    static let defaultActivity = 1.725

    struct Activity: Identifiable, Hashable {
        let value: Double
        let title: LocalizedStringResource
        let detail: LocalizedStringResource
        var id: Double { value }
    }

    static let activities: [Activity] = [
        Activity(value: 1, title: "Podstawowa przemiana materii (BMR)", detail: "Bez aktywności"),
        Activity(value: 1.2, title: "Siedzący", detail: "Mało lub brak ćwiczeń"),
        Activity(value: 1.375, title: "Lekko aktywny", detail: "Lekkie ćwiczenia 1–3 dni w tygodniu"),
        Activity(value: 1.55, title: "Umiarkowanie aktywny", detail: "Lekkie lub umiarkowane ćwiczenia 4–5 dni w tygodniu"),
        Activity(value: 1.725, title: "Aktywny", detail: "Umiarkowane ćwiczenia 6–7 dni w tygodniu lub intensywne 3–4 dni"),
        Activity(value: 1.9, title: "Bardzo aktywny", detail: "Intensywne ćwiczenia 6–7 dni w tygodniu, treningi sportowe lub praca fizyczna"),
    ]

    /// Calorie deficits of the plans (kcal / day).
    static let mildDeficit = 250
    static let moderateDeficit = 500
    static let extremeDeficit = 1000

    struct Result: Equatable {
        let bmr: Int
        let maintain: Int
        var mild: Int { maintain - Calculator.mildDeficit }
        var loss: Int { maintain - Calculator.moderateDeficit }
        var extreme: Int { maintain - Calculator.extremeDeficit }
    }

    /// `male` = true uses +5, otherwise -161.
    static func calculate(male: Bool, age: Int, heightCm: Double, weightKg: Double, activity: Double) -> Result {
        let bmrRaw = 10 * weightKg + 6.25 * heightCm - 5 * Double(age) + (male ? 5 : -161)
        let bmr = jsRound(bmrRaw)
        return Result(bmr: bmr, maintain: jsRound(Double(bmr) * activity))
    }

    /// Macro suggestion: protein 1.8 g/kg, fat 0.8 g/kg, the rest from carbs.
    static func suggestMacros(kcal: Double, weightKg: Double) -> (protein: Double, fat: Double, carbs: Double) {
        let protein = Double(jsRound(1.8 * weightKg))
        let fat = Double(jsRound(0.8 * weightKg))
        let rest = kcal - protein * 4 - fat * 9
        return (protein, fat, Double(max(0, jsRound(rest / 4))))
    }

    /// JavaScript `Math.round` (halves round up, also for negatives).
    static func jsRound(_ value: Double) -> Int { Int((value + 0.5).rounded(.down)) }
}

extension Int {
    /// Grouped number, e.g. "2 450".
    var grouped: String { formatted(.number.grouping(.automatic)) }
}
