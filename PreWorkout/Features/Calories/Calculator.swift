import Foundation

/// Mifflin-St Jeor calculator; same constants and rounding as the web app
/// (`src/pages/Calculator`, `src/constants/storage.ts`, `src/lib/goals.ts`).
enum Calculator {
    struct Activity: Identifiable {
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

    /// JavaScript `Math.round` (halves round up, also for negatives).
    static func jsRound(_ value: Double) -> Int { (value + 0.5).rounded(.down).safeInt }
}

extension Int {
    /// Grouped number, e.g. "2 450".
    var grouped: String { formatted(.number.grouping(.automatic)) }
}
