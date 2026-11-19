import SwiftUI

struct MoreView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        NavigationStack {
            List {
                if appState.people.count > 1 {
                    Section("Osoba") {
                        Picker("Aktywna osoba", selection: $appState.activePersonId) {
                            ForEach(appState.people) { person in
                                Text(person.displayName).tag(person.id)
                            }
                        }
                    }
                }

                Section("Trening") {
                    NavigationLink { ExercisesView() } label: { Label("Ćwiczenia", systemImage: "books.vertical") }
                    NavigationLink { MusclesView() } label: { Label("Mięśnie", systemImage: "figure.stand") }
                }

                Section("Narzędzia") {
                    NavigationLink { CalculatorView() } label: { Label("Kalkulator", systemImage: "function") }
                }

                Section("Ustawienia") {
                    NavigationLink { ProfileView() } label: { Label("Profil", systemImage: "person") }
                    NavigationLink { CategoriesView() } label: { Label("Kategorie", systemImage: "tag") }
                }

                Section {
                    LabeledContent("Serwer", value: ServerConfig.baseURL?.host() ?? "–")
                    LabeledContent("Wersja", value: Self.version)
                    Button("Wyloguj", role: .destructive) { Task { await appState.logout() } }
                }
            }
            .navigationTitle("Więcej")
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}

// MARK: Exercise library

struct ExercisesView: View {
    @State private var query = ""
    @State private var results: [ExerciseRef] = []
    @State private var error: String?

    var body: some View {
        List(results) { exercise in
            NavigationLink(exercise.name) { ExerciseDetailView(exerciseId: exercise.id) }
        }
        .overlay {
            if let error {
                ContentUnavailableView("Błąd", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if results.isEmpty && !query.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .searchable(text: $query, prompt: "Szukaj ćwiczeń")
        .navigationTitle("Ćwiczenia")
        .task(id: query) {
            // Debounce typing; FTS search on the server.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            do {
                results = try await APIClient.shared.searchExercises(query, limit: query.isEmpty ? 100 : 50)
                error = nil
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }
}

struct ExerciseDetailView: View {
    let exerciseId: String
    @State private var state: LoadState<Exercise> = .idle

    var body: some View {
        LoadStateView(state: state, retry: load) { exercise in
            List {
                Section {
                    LabeledContent("Kategoria", value: exercise.category)
                    LabeledContent("Typ", value: exercise.modality)
                    if let difficulty = exercise.difficulty { LabeledContent("Poziom", value: difficulty) }
                    LabeledContent("Pomiar", value: exercise.measurement)
                }
                if !exercise.muscles.isEmpty {
                    Section("Mięśnie") { Text(exercise.muscles.joined(separator: ", ")) }
                }
                if !exercise.equipment.isEmpty {
                    Section("Sprzęt") { Text(exercise.equipment.joined(separator: ", ")) }
                }
                if !exercise.variants.isEmpty {
                    Section("Warianty") { ForEach(exercise.variants, id: \.self) { Text($0) } }
                }
                if !exercise.description.isEmpty {
                    Section("Opis") { Text(exercise.description).font(.callout) }
                }
            }
            .navigationTitle(exercise.name)
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        state = .loading
        do { state = .loaded(try await APIClient.shared.exercise(exerciseId)) } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

/// 3D muscle map + heatmap: later milestone (web uses a GLB model; native
/// option: SceneKit/RealityKit with the same model, or a 2D body map).
struct MusclesView: View {
    var body: some View {
        ContentUnavailableView("Mapa mięśni", systemImage: "figure.stand",
                               description: Text("Pojawi się w kolejnej wersji."))
            .navigationTitle("Mięśnie")
    }
}

// MARK: Profile + categories

struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @State private var settings: UserSettings?
    @State private var saved: UserSettings?
    @State private var error: String?

    var body: some View {
        Form {
            if let binding = Binding($settings) {
                TextField("Imię", text: binding.name)
                TextField("Wiek", text: binding.age).keyboardType(.numberPad)
                TextField("Wzrost (cm)", text: binding.height).keyboardType(.numberPad)
                Picker("Płeć", selection: binding.sex) {
                    Text("–").tag("")
                    Text("Mężczyzna").tag("male")
                    Text("Kobieta").tag("female")
                }
            } else if error == nil {
                ProgressView()
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Profil")
        .toolbar {
            Button("Zapisz") { Task { await save() } }
                .disabled(settings == nil || settings == saved)
        }
        .task {
            do {
                let loaded = try await APIClient.shared.settings(person: appState.activePersonId)
                settings = loaded
                saved = loaded
            } catch { self.error = error.localizedDescription }
        }
    }

    private func save() async {
        guard let settings else { return }
        do {
            try await APIClient.shared.saveSettings(settings, person: appState.activePersonId)
            saved = settings
            try? await appState.loadPeople()
        } catch { self.error = error.localizedDescription }
    }
}

struct CategoriesView: View {
    @Environment(AppState.self) private var appState
    @State private var state: LoadState<[ActivityCategory]> = .idle

    var body: some View {
        LoadStateView(state: state, retry: load) { categories in
            List(categories) { category in
                HStack {
                    Text(category.name)
                    Spacer()
                    if category.archived == true {
                        Text("Archiwum").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Kategorie")
        .task { await load() }
    }

    private func load() async {
        state = .loading
        do { state = .loaded(try await APIClient.shared.categories(person: appState.activePersonId)) } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
