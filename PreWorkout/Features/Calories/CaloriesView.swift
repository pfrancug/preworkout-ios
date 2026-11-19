import SwiftUI

/// Tab: calorie calculator (Mifflin-St Jeor) and the saved daily goal.
struct CaloriesView: View {
    var body: some View {
        NavigationStack {
            CalculatorView()
        }
    }
}

struct CalculatorView: View {
    @Environment(AppState.self) private var appState

    // Calculator inputs (not saved, prefilled from the profile and the diary)
    @State private var male = true
    @State private var age: Int? = Calculator.defaultAge
    @State private var height: Double? = Double(Calculator.defaultHeight)
    @State private var weight: Double? = Calculator.defaultWeight
    @State private var activity = Calculator.defaultActivity
    @State private var prefilled = false
    @State private var weightNote: String?

    // Saved goal
    @State private var goalState: LoadState<NutritionGoal?> = .idle
    @State private var history: [NutritionGoalVersion] = []
    @State private var goal = NutritionGoalInput()
    @State private var saving = false
    @State private var error: String?
    @State private var saved = 0
    @State private var picked = 0
    @State private var confirmClear = false
    @State private var showEquation = false

    private var result: Calculator.Result? {
        guard let age, let height, let weight, age > 0, height > 0, weight > 0 else { return nil }
        return Calculator.calculate(male: male, age: age, heightCm: height, weightKg: weight, activity: activity)
    }

    var body: some View {
        Form {
            inputSection
            if let result {
                resultSection(result)
                plansSection(result)
            }
            goalSection
            historySection
            equationSection
        }
        .navigationTitle("Kalorie")
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await load(prefill: false) }
        .sensoryFeedback(.success, trigger: saved)
        .sensoryFeedback(.selection, trigger: picked)
        .sensoryFeedback(.error, trigger: error) { _, new in new != nil }
        .confirmationDialog("Usunąć cel dzienny?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Usuń cel", role: .destructive) { Task { await save(clear: true) } }
        } message: {
            Text("Usunięcie zostanie zapisane w historii celu.")
        }
        .task {
            if goalState.isIdle { await load(prefill: true) }
        }
    }

    // MARK: Sections

    private var inputSection: some View {
        Section {
            Picker("Płeć", selection: $male) {
                Text("Mężczyzna").tag(true)
                Text("Kobieta").tag(false)
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)
            IntField("Wiek", value: $age, unit: String(localized: "lat"))
            DecimalField("Wzrost", value: $height, unit: "cm")
            DecimalField("Waga", value: $weight, unit: "kg")
            Picker("Poziom aktywności", selection: $activity) {
                ForEach(Calculator.activities) { option in
                    VStack(alignment: .leading) {
                        Text(option.title)
                        Text(option.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(option.value)
                }
            }
            .pickerStyle(.navigationLink)
        } header: {
            Text("Twoje dane")
        } footer: {
            if let weightNote { Text(weightNote) }
        }
    }

    private func resultSection(_ result: Calculator.Result) -> some View {
        Section {
            VStack(spacing: 4) {
                Text("Dzienne zapotrzebowanie (TDEE)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(result.maintain.grouped)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: result.maintain)
                Text("kcal / dzień")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            LabeledContent("Podstawowa przemiana materii (BMR)") {
                Text(verbatim: "\(result.bmr.grouped) kcal").monospacedDigit()
            }
        }
    }

    private func plansSection(_ result: Calculator.Result) -> some View {
        Section {
            planRow("Utrzymanie wagi", kcal: result.maintain, deficit: 0, color: .green, icon: "scalemass")
            planRow("Łagodna utrata wagi", kcal: result.mild, deficit: Calculator.mildDeficit, color: .yellow, icon: "chart.line.downtrend.xyaxis")
            planRow("Utrata wagi", kcal: result.loss, deficit: Calculator.moderateDeficit, color: .orange, icon: "arrow.down")
            planRow("Ekstremalna utrata wagi", kcal: result.extreme, deficit: Calculator.extremeDeficit, color: .red, icon: "bolt.fill")
        } header: {
            Text("Plany kaloryczne")
        } footer: {
            Text("Dotknij planu, aby wpisać jego kalorie do celu dziennego.")
        }
    }

    private func planRow(_ title: LocalizedStringKey, kcal: Int, deficit: Int, color: Color, icon: String) -> some View {
        Button {
            goal.kcal = Double(kcal)
            picked += 1
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    if deficit > 0 {
                        Text("−\(deficit) kcal deficytu")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(kcal.grouped).font(.headline).monospacedDigit().foregroundStyle(.primary)
                    Text("kcal / dzień").font(.caption2).foregroundStyle(.secondary)
                }
                if goal.kcal == Double(kcal) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                }
            }
        }
    }

    @ViewBuilder
    private var goalSection: some View {
        Section {
            switch goalState {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity)
            case .failed(let message):
                ErrorText(message: message)
                Button("Spróbuj ponownie") { Task { await load(prefill: false) } }
            case .loaded(let current):
                if let current, let updated = current.updatedAt {
                    LabeledContent("Zapisany cel") {
                        Text(GoalFormat.summary(current.kcal, current.protein, current.fat, current.carbs))
                            .multilineTextAlignment(.trailing)
                    }
                    .accessibilityHint(Text(DayString.label(String(updated.prefix(10)))))
                }
                DecimalField("Kalorie", value: $goal.kcal, unit: "kcal")
                DecimalField("Białko", value: $goal.protein, unit: "g")
                DecimalField("Tłuszcz", value: $goal.fat, unit: "g")
                DecimalField("Węglowodany", value: $goal.carbs, unit: "g")
                if let weight, weight > 0 {
                    Button("Zaproponuj makro dla \(weight.short()) kg", systemImage: "wand.and.stars") {
                        suggest(weightKg: weight)
                    }
                    .disabled((goal.kcal ?? 0) <= 0)
                }
                Button {
                    Task { await save(clear: false) }
                } label: {
                    HStack {
                        Text("Zapisz cel").bold()
                        Spacer()
                        if saving { ProgressView() }
                    }
                }
                .disabled(saving || (goal.kcal ?? 0) <= 0)
                if current != nil {
                    Button("Usuń cel", role: .destructive) { confirmClear = true }
                        .disabled(saving)
                }
                if let error { ErrorText(message: error) }
            }
        } header: {
            Text("Cel dzienny")
        } footer: {
            Text("Dzień jest „w celu”, gdy wartość mieści się w ±10% celu. Makro są opcjonalne. Zmiany celu są zapisywane w historii.")
        }
    }

    @ViewBuilder
    private var historySection: some View {
        if history.count >= 2 {
            Section {
                ForEach(history.prefix(6)) { version in
                    GoalVersionRow(version: version)
                }
                if history.count > 6 {
                    NavigationLink("Cała historia") { GoalHistoryView(history: history) }
                }
            } header: {
                Text("Historia celu")
            }
        }
    }

    private var equationSection: some View {
        Section {
            DisclosureGroup("Jak to jest obliczane?", isExpanded: $showEquation) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Równanie Mifflin-St Jeor jest uważane za najdokładniejsze do obliczania podstawowej przemiany materii (BMR).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mężczyzna").font(.footnote.bold())
                        Text(verbatim: "BMR = 10 × kg + 6.25 × cm − 5 × age + 5")
                            .font(.footnote.monospaced())
                        Text("Kobieta").font(.footnote.bold()).padding(.top, 4)
                        Text(verbatim: "BMR = 10 × kg + 6.25 × cm − 5 × age − 161")
                            .font(.footnote.monospaced())
                    }
                    Text("TDEE = BMR × współczynnik aktywności")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: Actions

    private func suggest(weightKg: Double) {
        guard let kcal = goal.kcal, kcal > 0 else { return }
        let macros = Calculator.suggestMacros(kcal: kcal, weightKg: weightKg)
        goal.protein = macros.protein
        goal.fat = macros.fat
        goal.carbs = macros.carbs
        picked += 1
    }

    private func load(prefill: Bool) async {
        let person = appState.activePersonId
        if goalState.value == nil { goalState = .loading }
        async let goalTask = APIClient.shared.goal(person: person)
        async let historyTask = APIClient.shared.goalHistory(person: person)
        do {
            let current = try await goalTask
            goalState = .loaded(current)
            goal = NutritionGoalInput(kcal: current?.kcal, protein: current?.protein,
                                      fat: current?.fat, carbs: current?.carbs)
        } catch {
            if !Task.isCancelled && goalState.value == nil { goalState = .failed(error.localizedDescription) }
        }
        history = ((try? await historyTask) ?? []).sorted { $0.validFrom > $1.validFrom }

        guard prefill, !prefilled else { return }
        prefilled = true
        if let settings = try? await APIClient.shared.settings(person: person) {
            if settings.sex == "female" { male = false } else if settings.sex == "male" { male = true }
            if let value = Int(settings.age), value > 0 { age = value }
            if let value = Double(settings.height), value > 0 { height = value }
        }
        if let latest = try? await APIClient.shared.latestWeight(person: person) {
            weight = latest.kg
            weightNote = String(localized: "Waga z dziennika: \(DayString.label(latest.date)).")
        }
    }

    private func save(clear: Bool) async {
        let body: NutritionGoalInput
        if clear {
            body = NutritionGoalInput()
        } else {
            func clean(_ value: Double?) -> Double? {
                guard let value, value > 0 else { return nil }
                return Double(Calculator.jsRound(value))
            }
            body = NutritionGoalInput(kcal: clean(goal.kcal), protein: clean(goal.protein),
                                      fat: clean(goal.fat), carbs: clean(goal.carbs))
            if [body.kcal, body.protein, body.fat, body.carbs].contains(where: { ($0 ?? 0) > 20_000 }) {
                error = String(localized: "Wartość celu może wynosić najwyżej 20 000.")
                return
            }
        }
        saving = true
        error = nil
        defer { saving = false }
        do {
            let saved = try await APIClient.shared.saveGoal(body, person: appState.activePersonId)
            let isEmpty = saved.kcal == nil && saved.protein == nil && saved.fat == nil && saved.carbs == nil
            goalState = .loaded(isEmpty ? nil : saved)
            goal = body
            self.saved += 1
            history = ((try? await APIClient.shared.goalHistory(person: appState.activePersonId)) ?? history)
                .sorted { $0.validFrom > $1.validFrom }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

enum GoalFormat {
    /// "2 300 kcal · B 140 g · T 60 g · W 290 g" (missing values as "–").
    static func summary(_ kcal: Double?, _ protein: Double?, _ fat: Double?, _ carbs: Double?) -> String {
        func value(_ v: Double?) -> String { v.map { Calculator.jsRound($0).grouped } ?? "–" }
        return String(localized: "\(value(kcal)) kcal · B \(value(protein)) g · T \(value(fat)) g · W \(value(carbs)) g")
    }
}

struct GoalVersionRow: View {
    let version: NutritionGoalVersion

    var body: some View {
        LabeledContent {
            if version.isRemoval {
                Text("cel usunięty").foregroundStyle(.secondary)
            } else {
                Text(GoalFormat.summary(version.kcal, version.protein, version.fat, version.carbs))
                    .font(.footnote)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
            }
        } label: {
            Text(DayString.label(version.validFrom))
        }
    }
}

struct GoalHistoryView: View {
    let history: [NutritionGoalVersion]

    var body: some View {
        List(history) { GoalVersionRow(version: $0) }
            .navigationTitle("Historia celu")
            .navigationBarTitleDisplayMode(.inline)
    }
}
