import SwiftUI

/// Everything the calculator shows, kept per person on the phone so the tab
/// opens with real values at once. Empty until something is known: no
/// made-up defaults.
struct CalculatorCache: Codable, Equatable {
    var male: Bool?
    var age: Int?
    var height: Double?
    var weight: Double?
    var weightDate: String?
    var activity: Double?
    /// Last values seen on the server: applied again only when they change there,
    /// so a local edit isn't overwritten by every refresh.
    var serverSex: String?
    var serverAge: Int?
    var serverHeight: Double?
    var serverWeight: Double?
    var serverWeightDate: String?
    var serverActivity: Double?
    var serverCalcWeight: Double?
    var goal: NutritionGoal?
    var goalLoaded = false
    var history: [NutritionGoalVersion] = []

    private static func key(_ person: String) -> String { "preworkout.calculator.\(person)" }

    static func load(_ person: String) -> CalculatorCache? {
        guard let data = UserDefaults.standard.data(forKey: key(person)) else { return nil }
        return try? JSONDecoder().decode(CalculatorCache.self, from: data)
    }

    func save(_ person: String) {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key(person)) }
    }
}

struct CalculatorView: View {
    @Environment(AppState.self) private var appState

    @State private var data = CalculatorCache()
    @State private var restored = false
    @State private var profile: UserSettings?
    @State private var persistTask: Task<Void, Never>?
    @State private var applyingServer = false

    // Saved goal
    @State private var goalState: LoadState<NutritionGoal?> = .idle
    @State private var goal = NutritionGoalInput()
    @State private var saving = false
    @State private var savingPlan: Int?
    @State private var error: String?
    @State private var saved = 0
    @State private var confirmClear = false
    @State private var confirmPlanOff = false
    @State private var showEquation = false

    private var result: Calculator.Result? {
        guard let male = data.male, let age = data.age, let height = data.height, let weight = data.weight,
              let activity = data.activity, age > 0, height > 0, weight > 0 else { return nil }
        return Calculator.calculate(male: male, age: age, heightCm: height, weightKg: weight, activity: activity)
    }

    private var savedGoal: NutritionGoal? { goalState.value ?? nil }

    /// Calculator inputs still empty, in form order.
    private var missingFields: [String] {
        var missing: [String] = []
        if data.male == nil { missing.append(String(localized: "płeć")) }
        if (data.age ?? 0) <= 0 { missing.append(String(localized: "wiek")) }
        if (data.height ?? 0) <= 0 { missing.append(String(localized: "wzrost")) }
        if (data.weight ?? 0) <= 0 { missing.append(String(localized: "waga")) }
        if data.activity == nil { missing.append(String(localized: "poziom aktywności")) }
        return missing
    }

    var body: some View {
        Form {
            inputSection
            if let result {
                resultSection(result)
                plansSection(result)
            } else {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Brakuje: \(ListFormatter.localizedString(byJoining: missingFields))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.orange)
                            Text("Uzupełnij je, aby zobaczyć zapotrzebowanie i wybrać plan kaloryczny.")
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "list.bullet.clipboard").foregroundStyle(.orange)
                    }
                } header: {
                    Text("Plan kaloryczny")
                }
            }
            goalSection
            historySection
            equationSection
        }
        .navigationTitle("Kalorie")
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await refresh() }
        .sensoryFeedback(.success, trigger: saved)
        .sensoryFeedback(.error, trigger: error) { _, new in new != nil }
        .alert("Usunąć cel dzienny?", isPresented: $confirmClear) {
            Button("Usuń cel", role: .destructive) { Task { await save(clear: true) } }
            Button("Anuluj", role: .cancel) {}
        } message: {
            Text("Usunięcie zostanie zapisane w historii celu.")
        }
        .alert("Wyłączyć plan kaloryczny?", isPresented: $confirmPlanOff) {
            Button("Wyłącz plan", role: .destructive) { Task { await save(clear: true) } }
            Button("Anuluj", role: .cancel) {}
        } message: {
            Text("Cel dzienny zostanie usunięty. Zmiana trafi do historii celu.")
        }
        .onAppear(perform: restore)
        .onChange(of: data) { _, value in
            value.save(appState.activePersonId)
            queuePersist()
        }
        .task { await refresh() }
    }

    // MARK: Sections

    private var inputSection: some View {
        Section {
            Picker("Płeć", selection: $data.male) {
                Text("Mężczyzna").tag(Bool?.some(true))
                Text("Kobieta").tag(Bool?.some(false))
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)
            IntField("Wiek", value: $data.age, unit: String(localized: "lat"))
            DecimalField("Wzrost", value: $data.height, unit: "cm")
            DecimalField("Waga", value: $data.weight, unit: "kg")
            Picker("Poziom aktywności", selection: $data.activity) {
                Text("Wybierz").tag(Double?.none)
                ForEach(Calculator.activities) { option in
                    VStack(alignment: .leading) {
                        Text(option.title)
                        Text(option.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(Double?.some(option.value))
                }
            }
            .pickerStyle(.navigationLink)
        } header: {
            Text("Twoje dane")
        } footer: {
            if let date = data.weightDate, data.weight != nil, data.weight == data.serverWeight {
                Text("Waga z dziennika: \(DayString.label(date)).")
            }
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

    private struct Plan: Identifiable {
        let id: String
        let title: LocalizedStringKey
        let kcal: Int
        let deficit: Int
        let color: Color
        let icon: String
    }

    private func plans(_ result: Calculator.Result) -> [Plan] {
        [
            Plan(id: "maintain", title: "Utrzymanie wagi", kcal: result.maintain, deficit: 0, color: .green, icon: "scalemass"),
            Plan(id: "mild", title: "Łagodna utrata wagi", kcal: result.mild, deficit: Calculator.mildDeficit, color: .yellow, icon: "chart.line.downtrend.xyaxis"),
            Plan(id: "loss", title: "Utrata wagi", kcal: result.loss, deficit: Calculator.moderateDeficit, color: .orange, icon: "arrow.down"),
            Plan(id: "extreme", title: "Ekstremalna utrata wagi", kcal: result.extreme, deficit: Calculator.extremeDeficit, color: .red, icon: "bolt.fill"),
        ]
    }

    /// Active plan = the saved daily goal's calories.
    private var activeKcal: Int? { savedGoal?.kcal.map { Calculator.jsRound($0) } }

    private func plansSection(_ result: Calculator.Result) -> some View {
        let list = plans(result)
        let active = activeKcal
        let matches = list.contains { $0.kcal == active }
        return Section {
            ForEach(list) { plan in
                planCard(plan, isActive: plan.kcal == active)
            }
            if let active, !matches {
                HStack(spacing: 12) {
                    Image(systemName: "target")
                        .foregroundStyle(.tint)
                        .frame(width: 36, height: 36)
                        .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Własny cel")
                        Text("Nie pasuje do żadnego planu").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(verbatim: "\(active.grouped) kcal").font(.headline).monospacedDigit()
                    ActiveBadge()
                }
            }
            if active != nil {
                Button("Wyłącz plan", systemImage: "xmark.circle", role: .destructive) { confirmPlanOff = true }
                    .disabled(saving)
            }
        } header: {
            Text("Wybierz plan kaloryczny")
        } footer: {
            if active == nil {
                Text("Nie masz aktywnego planu. Dotknij planu, aby ustawić go jako cel dzienny.")
            } else {
                Text("Dotknij innego planu, aby go zmienić. Dotknij aktywnego planu albo „Wyłącz plan”, aby go wyłączyć.")
            }
        }
    }

    private func planCard(_ plan: Plan, isActive: Bool) -> some View {
        Button {
            if isActive {
                confirmPlanOff = true
            } else {
                Task { await choose(plan.kcal) }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: plan.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isActive ? .white : plan.color)
                    .frame(width: 36, height: 36)
                    .background(isActive ? plan.color : plan.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.title)
                        .fontWeight(isActive ? .semibold : .regular)
                        .foregroundStyle(.primary)
                    if plan.deficit > 0 {
                        Text("−\(plan.deficit) kcal deficytu")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(plan.kcal.grouped).font(.headline).monospacedDigit().foregroundStyle(.primary)
                    if isActive {
                        ActiveBadge()
                    } else {
                        Text("kcal / dzień").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Group {
                    if savingPlan == plan.kcal {
                        ProgressView()
                    } else {
                        Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(isActive ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
                    }
                }
                .frame(width: 28)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .disabled(saving)
        .listRowBackground(isActive ? plan.color.opacity(0.12) : Color(.secondarySystemGroupedBackground))
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityHint(isActive ? Text("Dotknij, aby wyłączyć plan") : Text("Dotknij, aby ustawić jako cel dzienny"))
    }

    @ViewBuilder
    private var goalSection: some View {
        Section {
            switch goalState {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity)
            case .failed(let message):
                ErrorText(message: message)
                Button("Spróbuj ponownie") { Task { await refresh() } }
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
                Button {
                    Task { await save(clear: false) }
                } label: {
                    HStack {
                        Text("Zapisz cel").bold()
                        Spacer()
                        if saving && savingPlan == nil { ProgressView() }
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
        if data.history.count >= 2 {
            Section {
                ForEach(data.history.prefix(6)) { version in
                    GoalVersionRow(version: version)
                }
                if data.history.count > 6 {
                    NavigationLink("Cała historia") { GoalHistoryView(history: data.history) }
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

    // MARK: Data

    private static func input(_ g: NutritionGoal?) -> NutritionGoalInput {
        NutritionGoalInput(kcal: g?.kcal, protein: g?.protein, fat: g?.fat, carbs: g?.carbs)
    }

    /// Cached values first (no flash of defaults or spinners).
    private func restore() {
        guard !restored else { return }
        restored = true
        guard let cached = CalculatorCache.load(appState.activePersonId) else { return }
        data = cached
        if cached.goalLoaded {
            goalState = .loaded(cached.goal)
            goal = Self.input(cached.goal)
        }
    }

    /// Silent refresh from the server; only what changed there is applied.
    private func refresh() async {
        restore()
        let person = appState.activePersonId
        if goalState.value == nil { goalState = .loading }
        async let goalTask = APIClient.shared.goal(person: person)
        async let historyTask = APIClient.shared.goalHistory(person: person)
        async let settingsTask = APIClient.shared.settings(person: person)
        async let weightTask = APIClient.shared.latestWeight(person: person)
        do {
            let current = try await goalTask
            // Keep unsaved edits of the goal fields.
            if goal == Self.input(data.goal) || !data.goalLoaded { goal = Self.input(current) }
            goalState = .loaded(current)
            data.goal = current
            data.goalLoaded = true
        } catch {
            if !Task.isCancelled && goalState.value == nil { goalState = .failed(error.localizedDescription) }
        }
        if let history = try? await historyTask {
            data.history = history.sorted { $0.validFrom > $1.validFrom }
        }
        applyingServer = true
        defer { applyingServer = false }
        if let settings = try? await settingsTask {
            profile = settings
            if !settings.sex.isEmpty, settings.sex != data.serverSex {
                data.serverSex = settings.sex
                data.male = settings.sex == "male"
            }
            if let age = Int(settings.age), age > 0, age != data.serverAge {
                data.serverAge = age
                data.age = age
            }
            if let height = Double(settings.height), height > 0, height != data.serverHeight {
                data.serverHeight = height
                data.height = height
            }
            if let activity = settings.activity, activity != data.serverActivity {
                data.serverActivity = activity
                data.activity = activity
            }
            if let kg = Self.parseWeight(settings.weight), kg > 0, kg != data.serverCalcWeight {
                data.serverCalcWeight = kg
                data.weight = kg
            }
        }
        // Diary weight fills the field only when the profile has no calculator weight yet.
        if data.serverCalcWeight == nil, let latest = try? await weightTask,
           latest.kg != data.serverWeight || latest.date != data.serverWeightDate {
            data.serverWeight = latest.kg
            data.serverWeightDate = latest.date
            data.weight = latest.kg
            data.weightDate = latest.date
        }
        // First sync: upload activity or weight that lived only on the phone.
        let settings = profile
        if (settings?.activity == nil && data.activity != nil)
            || (Self.parseWeight(settings?.weight ?? "") == nil && data.weight != nil) {
            applyingServer = false
            await persistCalculatorFields()
        }
    }

    private static func parseWeight(_ raw: String) -> Double? {
        let text = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(text), value > 0 else { return nil }
        return value
    }

    private static func weightText(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value.rounded())) : String(format: "%.2f", value)
    }

    private func queuePersist() {
        guard !applyingServer else { return }
        persistTask?.cancel()
        persistTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await persistCalculatorFields()
        }
    }

    /// Writes calculator inputs into the profile so they follow the account.
    private func persistCalculatorFields() async {
        let person = appState.activePersonId
        guard !person.isEmpty else { return }
        var settings = profile
            ?? DiskCache.read("settings", person: person)
            ?? UserSettings(name: "", age: "", height: "", sex: "")
        if let male = data.male { settings.sex = male ? "male" : "female" }
        if let age = data.age, age > 0 { settings.age = String(age) }
        if let height = data.height, height > 0 {
            settings.height = height == height.rounded() ? String(Int(height.rounded())) : String(height)
        }
        if let weight = data.weight, weight > 0 { settings.weight = Self.weightText(weight) }
        settings.activity = data.activity
        do {
            try await APIClient.shared.saveSettings(settings, person: person)
            profile = settings
            data.serverSex = settings.sex
            if let age = Int(settings.age) { data.serverAge = age }
            if let height = Double(settings.height) { data.serverHeight = height }
            data.serverActivity = settings.activity
            data.serverCalcWeight = Self.parseWeight(settings.weight)
        } catch {
            if self.error == nil { self.error = error.localizedDescription }
        }
    }

    /// Plan picked: its calories become the daily goal right away (macros stay).
    private func choose(_ kcal: Int) async {
        savingPlan = kcal
        defer { savingPlan = nil }
        goal.kcal = Double(kcal)
        await save(clear: false)
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
            let current: NutritionGoal? = saved.flatMap { g -> NutritionGoal? in
                g.kcal == nil && g.protein == nil && g.fat == nil && g.carbs == nil ? nil : g
            }
            goalState = .loaded(current)
            data.goal = current
            data.goalLoaded = true
            goal = body
            self.saved += 1
            if let history = try? await APIClient.shared.goalHistory(person: appState.activePersonId) {
                data.history = history.sorted { $0.validFrom > $1.validFrom }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Green "Active" capsule on the active calorie plan.
private struct ActiveBadge: View {
    var body: some View {
        Text("Aktywny")
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.green, in: Capsule())
    }
}

enum GoalFormat {
    /// "2 300 kcal · B 140 g · T 60 g · W 290 g"; only "2 300 kcal" unless all three macros are set.
    static func summary(_ kcal: Double?, _ protein: Double?, _ fat: Double?, _ carbs: Double?) -> String {
        func value(_ v: Double?) -> String { v.map { Calculator.jsRound($0).grouped } ?? "–" }
        guard let protein, let fat, let carbs, protein > 0, fat > 0, carbs > 0 else {
            return String(localized: "\(value(kcal)) kcal")
        }
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
