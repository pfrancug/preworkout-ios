import PhotosUI
import SwiftUI

/// Tab: profile of the active person (photo, personal data, body and daily goal),
/// person switch and app settings.
struct ProfileView: View {
    @State private var whatsNew = WhatsNewStore.shared
    @Environment(AppState.self) private var appState
    @State private var state: LoadState<UserSettings> = .idle
    @State private var form = UserSettings(name: "", age: "", height: "", sex: "", avatarUrl: nil)
    @State private var saving = false
    @State private var error: String?
    @State private var saved = 0
    @State private var photo: PhotosPickerItem?
    @State private var updatingPhoto = false
    @State private var goal: NutritionGoal?
    @State private var weight: (date: String, kg: Double)?

    var body: some View {
        @Bindable var appState = appState
        NavigationStack {
            Form {
                switch state {
                case .idle, .loading:
                    Section { ProgressView().frame(maxWidth: .infinity) }
                case .failed(let message):
                    Section {
                        ErrorText(message: message)
                        Button("Spróbuj ponownie") { Task { await load() } }
                    }
                case .loaded(let original):
                    headerSection(original)
                    personalSection(original)
                }

                if appState.people.count > 1 {
                    Section {
                        Picker("Osoba", selection: $appState.activePersonId) {
                            ForEach(appState.people) { person in
                                Text(person.displayName).tag(person.id)
                            }
                        }
                    } footer: {
                        Text("Treningi, profil i cel dotyczą wybranej osoby.")
                    }
                }

                if state.value != nil {
                    bodySection
                }

                Section {
                    NavigationLink {
                        WhatsNewView()
                    } label: {
                        HStack {
                            Label("Co nowego", systemImage: "sparkles")
                            if whatsNew.hasUnseen {
                                Spacer()
                                Circle().fill(Color.red).frame(width: 9, height: 9)
                                    .accessibilityLabel(Text("Nowe zmiany"))
                            }
                        }
                    }
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Ustawienia", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("Profil")
            .refreshable { await load() }
            .sensoryFeedback(.success, trigger: saved)
            .sensoryFeedback(.selection, trigger: appState.activePersonId)
            .sensoryFeedback(.error, trigger: error) { _, new in new != nil }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task { await setPhoto(item) }
            }
        }
        .task {
            if state.isIdle { await load() }
        }
    }

    // MARK: Sections

    private func headerSection(_ original: UserSettings) -> some View {
        Section {
            HStack(spacing: 16) {
                ZStack {
                    AvatarView(url: original.avatarUrl, name: displayName(original))
                    if updatingPhoto {
                        ProgressView()
                            .frame(width: 72, height: 72)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName(original))
                        .font(.title2.bold())
                    if let summary = summary(original) {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        PhotosPicker(selection: $photo, matching: .images) {
                            (hasAvatar(original) ? Text("Zmień zdjęcie") : Text("Dodaj zdjęcie"))
                                .font(.subheadline)
                        }
                        if hasAvatar(original) {
                            Button("Usuń", role: .destructive) { Task { await removePhoto() } }
                                .font(.subheadline)
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(updatingPhoto)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func personalSection(_ original: UserSettings) -> some View {
        Section {
            TextField("Imię", text: $form.name)
                .textContentType(.givenName)
            TextField("Nazwisko", text: $form.lastName)
                .textContentType(.familyName)
            Picker("Płeć", selection: $form.sex) {
                ForEach(["", "male", "female"], id: \.self) { Text(Labels.sex($0)).tag($0) }
            }
            LabeledContent("Wiek") {
                HStack(spacing: 4) {
                    TextField("–", text: $form.age)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                    Text("lat").foregroundStyle(.secondary)
                }
            }
            LabeledContent("Wzrost") {
                HStack(spacing: 4) {
                    TextField("–", text: $form.height)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                    Text(verbatim: "cm").foregroundStyle(.secondary)
                }
            }
            if hasChanges(original) {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Text("Zapisz zmiany").bold()
                        Spacer()
                        if saving { ProgressView() }
                    }
                }
                .disabled(saving)
            }
            if let error { ErrorText(message: error) }
        } header: {
            Text("Dane osobowe")
        } footer: {
            Text("Płeć, wiek i wzrost są używane w kalkulatorze kalorii.")
        }
    }

    private var bodySection: some View {
        Section {
            if let weight {
                LabeledContent("Waga") {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(verbatim: "\(weight.kg.short()) kg").monospacedDigit()
                        Text(DayString.label(weight.date)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let bmi {
                    LabeledContent("BMI", value: bmi.short())
                }
            }
            NavigationLink {
                CalculatorView()
            } label: {
                LabeledContent {
                    if let goal, goal.kcal != nil || goal.protein != nil || goal.fat != nil || goal.carbs != nil {
                        Text(GoalFormat.summary(goal.kcal, goal.protein, goal.fat, goal.carbs))
                            .font(.footnote)
                            .multilineTextAlignment(.trailing)
                    } else {
                        Text("Brak celu")
                    }
                } label: {
                    Label("Cel dzienny", systemImage: "target")
                }
            }
        } header: {
            Text("Ciało i odżywianie")
        }
    }

    // MARK: Helpers

    private func displayName(_ settings: UserSettings) -> String {
        let name = settings.displayName
        if !name.isEmpty { return name }
        return appState.activePerson?.displayName ?? String(localized: "Ja")
    }

    private func summary(_ s: UserSettings) -> String? {
        var parts: [String] = []
        if s.sex == "male" || s.sex == "female" { parts.append(String(localized: Labels.sex(s.sex))) }
        if let age = Int(s.age), age > 0 { parts.append(String(localized: "\(age) lat")) }
        if let height = Int(s.height), height > 0 { parts.append("\(height) cm") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func hasAvatar(_ s: UserSettings) -> Bool { !(s.avatarUrl ?? "").isEmpty }

    private func hasChanges(_ original: UserSettings) -> Bool {
        form.name != original.name || form.lastName != original.lastName
            || form.age != original.age || form.height != original.height || form.sex != original.sex
    }

    private var bmi: Double? {
        guard let weight, let cm = Double(state.value?.height ?? ""), cm > 0 else { return nil }
        let m = cm / 100
        return weight.kg / (m * m)
    }

    // MARK: Actions

    private func load() async {
        let person = appState.activePersonId
        if state.value == nil, let cached: UserSettings = DiskCache.read("settings", person: person) {
            form = cached
            state = .loaded(cached)
        }
        if goal == nil, let cached: NutritionGoal = DiskCache.read("goals", person: person) {
            goal = cached
        }
        if weight == nil, let rows: [DiaryRow] = DiskCache.read("diary", person: person) {
            weight = rows.filter { ($0.weight ?? 0) > 0 }.max { $0.date < $1.date }.map { (String($0.date.prefix(10)), $0.weight ?? 0) }
        }
        do {
            let settings = try await APIClient.shared.settings(person: person)
            form = settings
            state = .loaded(settings)
        } catch {
            guard !Task.isCancelled else { return }
            if state.value == nil { state = .failed(error.localizedDescription) } else { self.error = error.localizedDescription }
        }
        if let value = try? await APIClient.shared.goal(person: person) { goal = value } else { goal = nil }
        if let latest = try? await APIClient.shared.latestWeight(person: person) { weight = latest }
    }

    private func validated() -> UserSettings? {
        let age = form.age.trimmingCharacters(in: .whitespaces)
        let height = form.height.trimmingCharacters(in: .whitespaces)
        if let value = Int(age), !(1...150).contains(value) {
            error = String(localized: "Wiek musi być w zakresie 1–150.")
            return nil
        }
        if let value = Int(height), !(50...300).contains(value) {
            error = String(localized: "Wzrost musi być w zakresie 50–300 cm.")
            return nil
        }
        if (!age.isEmpty && Int(age) == nil) || (!height.isEmpty && Int(height) == nil) {
            error = String(localized: "Wiek i wzrost muszą być liczbami.")
            return nil
        }
        var body = form
        body.name = form.name.trimmingCharacters(in: .whitespaces)
        body.lastName = form.lastName.trimmingCharacters(in: .whitespaces)
        body.age = age
        body.height = height
        return body
    }

    private func save() async {
        guard let body = validated() else { return }
        saving = true
        error = nil
        defer { saving = false }
        await persist(body)
    }

    /// Saves the whole profile (the API replaces it) and refreshes the people list.
    private func persist(_ body: UserSettings) async {
        do {
            try await APIClient.shared.saveSettings(body, person: appState.activePersonId)
            form = body
            state = .loaded(body)
            saved += 1
            try? await appState.loadPeople()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func setPhoto(_ item: PhotosPickerItem) async {
        updatingPhoto = true
        defer {
            updatingPhoto = false
            photo = nil
        }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let url = AvatarView.dataURL(from: data),
              var body = state.value else {
            error = String(localized: "Nie udało się wczytać zdjęcia.")
            return
        }
        // Keep unsaved form edits out of the photo update.
        body.avatarUrl = url
        await persistPhoto(body)
    }

    private func removePhoto() async {
        guard var body = state.value else { return }
        updatingPhoto = true
        defer { updatingPhoto = false }
        body.avatarUrl = ""
        await persistPhoto(body)
    }

    private func persistPhoto(_ body: UserSettings) async {
        do {
            try await APIClient.shared.saveSettings(body, person: appState.activePersonId)
            state = .loaded(body)
            form.avatarUrl = body.avatarUrl
            saved += 1
            try? await appState.loadPeople()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
