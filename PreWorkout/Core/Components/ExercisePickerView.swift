import SwiftUI
import UIKit

/// Sheet: pick one exercise from the library (server full-text search).
/// Pass `placement` to push the next step on the same sheet (do not dismiss
/// and present another sheet: that crashes on iOS 26/27 when the search
/// keyboard is up).
struct ExercisePickerView<Placement: View>: View {
    let onPick: (Exercise) -> Void
    let placement: ((Exercise) -> Placement)?

    @Environment(ExerciseStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissSearch) private var dismissSearch
    @State private var query = ""
    @State private var results: [Exercise]?
    @State private var searching = false
    @State private var placing: Exercise?
    @State private var reportedEmptyQuery: String?

    init(onPick: @escaping (Exercise) -> Void) where Placement == EmptyView {
        self.onPick = onPick
        self.placement = nil
    }

    init(
        onPick: @escaping (Exercise) -> Void = { _ in },
        @ViewBuilder placement: @escaping (Exercise) -> Placement
    ) {
        self.onPick = onPick
        self.placement = placement
    }

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
            .navigationDestination(item: $placing) { exercise in
                if let placement {
                    placement(exercise)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
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

    private func pick(_ exercise: Exercise) {
        if placement != nil {
            // Stay on this sheet and push placement. Dismissing the search
            // sheet to present another one aborts in UIKeyboardLayoutGuide
            // on iOS 26/27 (TestFlight builds 29 and 31).
            dismissSearch()
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            placing = exercise
            return
        }
        onPick(exercise)
        dismiss()
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            results = nil
            reportedEmptyQuery = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        searching = true
        defer { searching = false }
        do {
            let refs = try await APIClient.shared.searchExercises(q)
            guard !Task.isCancelled else { return }
            var seen = Set<String>()
            results = refs.compactMap { store.byId[$0.id] }.filter { seen.insert($0.id).inserted }
            reportEmptySearchIfNeeded(query: q)
        } catch {
            // Offline / failed search: fall back to local matching.
            if !Task.isCancelled {
                results = nil
                reportEmptySearchIfNeeded(query: q)
            }
        }
    }

    /// Fires once per settled zero-result query. `query` is the normalized
    /// search text (not personal data) so missing exercises can be found.
    private func reportEmptySearchIfNeeded(query: String) {
        let normalized = Analytics.normalizedSearchQuery(query)
        guard visible.isEmpty, reportedEmptyQuery != normalized else { return }
        reportedEmptyQuery = normalized
        Analytics.send("ExerciseSearch.noResults", [
            "query": normalized,
            "queryLength": Analytics.queryLengthBucket(query.count),
        ])
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
