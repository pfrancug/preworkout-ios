import SwiftUI

/// Tab: exercise library with full-text search, filters and custom exercises.
struct ExercisesView: View {
    @Environment(ExerciseStore.self) private var store
    @State private var query = ""
    @State private var results: [Exercise]?
    @State private var searching = false
    @State private var modality: String?
    @State private var category: String?
    @State private var customOnly = false
    @State private var showArchived = false
    @State private var creating = false

    var body: some View {
        NavigationStack {
            List {
                if let error = store.error, store.all.isEmpty {
                    Section {
                        ErrorText(message: error)
                        Button("Spróbuj ponownie") { Task { await store.load() } }
                    }
                }
                Section {
                    ForEach(visible) { exercise in
                        NavigationLink {
                            ExerciseDetailView(exerciseId: exercise.id)
                        } label: {
                            ExerciseRow(exercise: exercise)
                        }
                    }
                } footer: {
                    if !visible.isEmpty {
                        Text("Ćwiczeń: \(visible.count)")
                    }
                }
            }
            .overlay {
                if store.isLoading && store.all.isEmpty {
                    ProgressView()
                } else if store.loaded, visible.isEmpty, !searching {
                    if query.isEmpty {
                        ContentUnavailableView("Brak ćwiczeń", systemImage: "figure.strengthtraining.traditional",
                                               description: Text("Zmień filtry albo dodaj własne ćwiczenie."))
                    } else {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
            .searchable(text: $query, prompt: Text("Nazwa, alias, mięsień…"))
            .refreshable { await store.load() }
            .navigationTitle("Ćwiczenia")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { filterMenu }
                ToolbarItem(placement: .primaryAction) {
                    Button("Nowe ćwiczenie", systemImage: "plus") { creating = true }
                }
            }
            .sheet(isPresented: $creating) {
                ExerciseEditorView(exercise: nil)
            }
            .task { await store.loadIfNeeded() }
            .task(id: query) { await search() }
        }
    }

    private var filtersActive: Bool { modality != nil || category != nil || customOnly || showArchived }

    private var filterMenu: some View {
        Menu {
            Picker("Rodzaj", selection: $modality) {
                Text("Wszystkie rodzaje").tag(String?.none)
                ForEach(Labels.modalities, id: \.self) { Text(Labels.modality($0)).tag(Optional($0)) }
            }
            .pickerStyle(.menu)
            Picker("Kategoria", selection: $category) {
                Text("Wszystkie kategorie").tag(String?.none)
                ForEach(Labels.categories, id: \.self) { Text(Labels.category($0)).tag(Optional($0)) }
            }
            .pickerStyle(.menu)
            Toggle("Tylko własne", isOn: $customOnly)
            Toggle("Pokaż zarchiwizowane", isOn: $showArchived)
            if filtersActive {
                Button("Wyczyść filtry", systemImage: "xmark.circle", role: .destructive) {
                    modality = nil
                    category = nil
                    customOnly = false
                    showArchived = false
                }
            }
        } label: {
            Image(systemName: filtersActive
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
    }

    private var visible: [Exercise] {
        let base = query.trimmingCharacters(in: .whitespaces).isEmpty ? store.all : (results ?? localMatches)
        return base.filter { e in
            (showArchived || !e.archived)
                && (!customOnly || e.isCustom)
                && (modality == nil || e.modality == modality)
                && (category == nil || e.category == category)
        }
    }

    private var localMatches: [Exercise] {
        let q = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return store.all.filter { e in
            ([e.name] + e.aliases + e.muscles).contains {
                $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains(q)
            }
        }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { results = nil; return }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        searching = true
        defer { searching = false }
        do {
            let refs = try await APIClient.shared.searchExercises(q, limit: 200)
            guard !Task.isCancelled else { return }
            results = refs.compactMap { store.byId[$0.id] }
        } catch {
            if !Task.isCancelled { results = nil }
        }
    }
}
