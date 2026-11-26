import SwiftUI
import UIKit

/// Sheet: pick one exercise from the library (server full-text search).
struct ExercisePickerView: View {
    let onPick: (Exercise) -> Void

    @Environment(ExerciseStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissSearch) private var dismissSearch
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
                        pick(exercise)
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
                    Button("Anuluj") { close() }
                }
            }
            .task { await store.loadIfNeeded() }
            .task(id: query) { await search() }
        }
    }

    /// Unique by id: a search hit can appear twice (name + alias) and ForEach
    /// would otherwise get duplicate identities.
    private var visible: [Exercise] {
        let list: [Exercise]
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            list = store.enabled.filter { !$0.archived }
        } else {
            list = (results ?? localMatches).filter(store.isEnabled)
        }
        var seen = Set<String>()
        return list.filter { seen.insert($0.id).inserted }
    }

    private var localMatches: [Exercise] {
        let q = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return store.all.filter { exercise in
            ([exercise.name] + exercise.aliases).contains {
                $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains(q)
            }
        }
    }

    /// Dismissing this sheet while the search keyboard is still first responder
    /// crashes on iOS 26/27 (UIKeyboardLayoutGuide Auto Layout). Hide the
    /// keyboard first, then dismiss after the keyboard animation starts.
    private func pick(_ exercise: Exercise) {
        resignKeyboard()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            onPick(exercise)
            dismiss()
        }
    }

    private func close() {
        resignKeyboard()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            dismiss()
        }
    }

    private func resignKeyboard() {
        dismissSearch()
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
            var seen = Set<String>()
            results = refs.compactMap { store.byId[$0.id] }.filter { seen.insert($0.id).inserted }
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
