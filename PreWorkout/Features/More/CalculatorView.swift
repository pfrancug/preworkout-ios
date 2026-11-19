import SwiftUI

/// TDEE / calorie calculator (Mifflin-St Jeor), same math as the web
/// `src/pages/Calculator/utils/calculate.ts`; "Zapisz cel" stores the daily kcal goal.
struct CalculatorView: View {
    @Environment(AppState.self) private var appState
    @State private var male = true
    @State private var age = 30.0
    @State private var height = 175.0
    @State private var weight = 75.0
    @State private var activity = 1.725
    @State private var message: String?

    private static let activities: [(Double, LocalizedStringKey)] = [
        (1, "BMR (bez aktywności)"),
        (1.2, "Siedzący tryb życia"),
        (1.375, "Lekka aktywność (1–3 dni/tydz.)"),
        (1.55, "Umiarkowana (4–5 dni/tydz.)"),
        (1.725, "Aktywny (6–7 dni/tydz.)"),
        (1.9, "Bardzo aktywny / praca fizyczna"),
    ]

    private var bmr: Int {
        Int((10 * weight + 6.25 * height - 5 * age + (male ? 5 : -161)).rounded())
    }

    private var maintain: Int { Int((Double(bmr) * activity).rounded()) }

    var body: some View {
        Form {
            Section("Dane") {
                Picker("Płeć", selection: $male) {
                    Text("Mężczyzna").tag(true)
                    Text("Kobieta").tag(false)
                }
                .pickerStyle(.segmented)
                Stepper("Wiek: \(Int(age))", value: $age, in: 10...100)
                Stepper("Wzrost: \(Int(height)) cm", value: $height, in: 100...230)
                Stepper("Waga: \(weight, specifier: "%.1f") kg", value: $weight, in: 30...250, step: 0.5)
                Picker("Aktywność", selection: $activity) {
                    ForEach(Self.activities, id: \.0) { value, label in
                        Text(label).tag(value)
                    }
                }
            }

            Section("Wynik") {
                LabeledContent("BMR", value: "\(bmr) kcal")
                row("Utrzymanie", maintain)
                row("Lekki deficyt (−250)", maintain - 250)
                row("Redukcja (−500)", maintain - 500)
                row("Mocna redukcja (−1000)", maintain - 1000)
            }

            if let message {
                Section { Text(message).font(.callout) }
            }
        }
        .navigationTitle("Kalkulator")
        .task { await prefill() }
    }

    private func row(_ title: LocalizedStringKey, _ kcal: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(kcal) kcal").monospacedDigit()
            Button("Zapisz cel") { Task { await saveGoal(kcal) } }
                .buttonStyle(.bordered).controlSize(.small)
        }
    }

    private func prefill() async {
        guard let s = try? await APIClient.shared.settings(person: appState.activePersonId) else { return }
        if let a = Double(s.age) { age = a }
        if let h = Double(s.height) { height = h }
        if !s.sex.isEmpty { male = s.sex == "male" }
    }

    private func saveGoal(_ kcal: Int) async {
        do {
            // Keep the saved macros, change only kcal.
            let current = try await APIClient.shared.goal(person: appState.activePersonId)
            let input = NutritionGoalInput(kcal: Double(kcal), protein: current?.protein,
                                           fat: current?.fat, carbs: current?.carbs)
            _ = try await APIClient.shared.saveGoal(input, person: appState.activePersonId)
            message = String(localized: "Zapisano cel: \(kcal) kcal")
        } catch {
            message = error.localizedDescription
        }
    }
}
