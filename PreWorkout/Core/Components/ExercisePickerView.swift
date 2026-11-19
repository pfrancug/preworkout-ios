import SwiftUI

/// Sheet: pick one exercise from the library (server full-text search).
struct ExercisePickerView: View {
    let onPick: (Exercise) -> Void

    @Environment(ExerciseStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [Exercise]?
    @State private var searching = false

    var body: some View {
        NavigationStack {
            List {
                if let error = store.error, store.all.isEmpty {
                    ErrorText(message: error)
                }
                ForEach(visible) { exercise in
                    Button {
                        onPick(exercise)
                        dismiss()
                    } label: {
                        ExerciseRow(exercise: exercise)
                    }
                    .tint(.primary)
                }
            }
            .listStyle(.plain)
            .overlay {
                if store.isLoading && store.all.isEmpty {
                    ProgressView()
                } else if !query.isEmpty, !searching, visible.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Szukaj ćwiczenia"))
            .navigationTitle("Wybierz ćwiczenie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
            }
            .task { await store.loadIfNeeded() }
            .task(id: query) { await search() }
        }
    }

    private var visible: [Exercise] {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            return store.all.filter { !$0.archived }
        }
        return results ?? localMatches
    }

    private var localMatches: [Exercise] {
        let q = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return store.all.filter { exercise in
            ([exercise.name] + exercise.aliases).contains {
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
            let refs = try await APIClient.shared.searchExercises(q)
            guard !Task.isCancelled else { return }
            results = refs.compactMap { store.byId[$0.id] }
        } catch {
            // Offline / failed search: fall back to local matching.
            if !Task.isCancelled { results = nil }
        }
    }
}

/// Library row: name, category · difficulty, custom / archived tags.
struct ExerciseRow: View {
    let exercise: Exercise

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(exercise.name)
                    .foregroundStyle(exercise.archived ? .secondary : .primary)
                if exercise.isCustom { Tag("Własne") }
                if exercise.archived { Tag("Archiwum", color: .secondary) }
            }
            HStack(spacing: 4) {
                Text(Labels.category(exercise.category))
                if let difficulty = exercise.difficulty {
                    Text(verbatim: "·")
                    Text(Labels.difficulty(difficulty))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
