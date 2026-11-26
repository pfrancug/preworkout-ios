import SwiftUI

/// Tab: body weight, BMI and the calorie calculator / daily goal.
struct BodyView: View {
    @Environment(AppState.self) private var appState
    @State private var weight: (date: String, kg: Double)?
    @State private var heightCm: Double?
    @State private var goal: NutritionGoal?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        WeightView()
                    } label: {
                        IconRow(
                            "Waga",
                            icon: "scalemass",
                            value: weight.map { "\($0.kg.short()) kg" } ?? String(localized: "Dodaj")
                        )
                    }
                    if let bmi {
                        IconRow("BMI", icon: "ruler", value: bmi.short())
                    }
                } header: {
                    Text("Ciało")
                }

                Section {
                    NavigationLink {
                        CalculatorView()
                    } label: {
                        IconRow("Kalorie i cel dzienny", icon: "flame", value: goalSummary)
                    }
                } header: {
                    Text("Odżywianie")
                }
            }
            .navigationTitle("Ciało")
            .onAppear { Task { await load() } }
            .refreshable { await load() }
            .onReceive(NotificationCenter.default.publisher(for: .outboxFlushed)) { _ in Task { await load() } }
        }
        .appNavigationChrome()
        .keepsTabBarVisible("body")
    }

    private var goalSummary: String {
        guard let goal, goal.kcal != nil || goal.protein != nil || goal.fat != nil || goal.carbs != nil else {
            return String(localized: "Brak celu")
        }
        return GoalFormat.summary(goal.kcal, goal.protein, goal.fat, goal.carbs)
    }

    private var bmi: Double? {
        guard let weight, let cm = heightCm, cm > 0 else { return nil }
        let m = cm / 100
        return weight.kg / (m * m)
    }

    private func load() async {
        let person = appState.activePersonId
        if weight == nil, let rows: [DiaryRow] = DiskCache.read("diary", person: person) {
            weight = rows.filter(\.hasAnyWeight)
                .max { $0.date < $1.date }
                .map { (String($0.date.prefix(10)), $0.displayWeight ?? 0) }
        }
        if heightCm == nil, let cached: UserSettings = DiskCache.read("settings", person: person) {
            heightCm = Double(cached.height)
        }
        if goal == nil, let cached: NutritionGoal = DiskCache.read("goals", person: person) {
            goal = cached
        }
        if let settings = try? await APIClient.shared.settings(person: person) {
            heightCm = Double(settings.height)
        }
        if let value = try? await APIClient.shared.goal(person: person) { goal = value } else { goal = nil }
        if let latest = try? await APIClient.shared.latestWeight(person: person) { weight = latest }
    }
}
