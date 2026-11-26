import SwiftUI

struct ExerciseDetailView: View {
    let exerciseId: String

    @Environment(ExerciseStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var loadError: String?
    @State private var editing = false
    @State private var editingAliases = false
    @State private var confirmDelete = false
    @State private var actionError: String?
    @State private var deleted = 0

    var body: some View {
        Group {
            if let exercise = store.byId[exerciseId] {
                content(exercise)
            } else if let loadError {
                ContentUnavailableView {
                    Label("Nie udało się wczytać", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Spróbuj ponownie") { Task { await refresh() } }
                }
            } else {
                ProgressView()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .alert("Błąd", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
        .sensoryFeedback(.success, trigger: deleted)
        .task { await refresh() }
    }

    private func content(_ exercise: Exercise) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(exercise.name).font(.title2.bold())
                    HStack(spacing: 6) {
                        Tag(resource: Labels.modality(exercise.modality))
                        Tag(resource: Labels.category(exercise.category), color: .blue)
                        if let difficulty = exercise.difficulty {
                            Tag(resource: Labels.difficulty(difficulty), color: .orange)
                        }
                        if exercise.isCustom { Tag("Własne", color: .purple) }
                        if exercise.archived { Tag("Archiwum", color: .secondary) }
                    }
                }
                .padding(.vertical, 4)
                LabeledContent("Pomiar") { Text(Labels.measurement(exercise.measurement)) }
                if let family = exercise.family, !family.isEmpty {
                    LabeledContent("Rodzina", value: family)
                }
            }

            if !exercise.muscles.isEmpty {
                Section("Mięśnie") {
                    if exercise.musclesPrimary.isEmpty {
                        Text(exercise.muscles.joined(separator: ", "))
                    } else {
                        LabeledContent("Główne") {
                            Text(exercise.musclesPrimary.joined(separator: ", ")).multilineTextAlignment(.trailing)
                        }
                        if !exercise.musclesSecondary.isEmpty {
                            LabeledContent("Pomocnicze") {
                                Text(exercise.musclesSecondary.joined(separator: ", ")).multilineTextAlignment(.trailing)
                            }
                        }
                    }
                }
            }

            if !exercise.equipment.isEmpty {
                Section("Sprzęt") { Text(exercise.equipment.joined(separator: ", ")) }
            }

            Section {
                if exercise.aliases.isEmpty {
                    Text("Brak aliasów").foregroundStyle(.secondary)
                } else {
                    ForEach(exercise.aliases, id: \.self) { Text($0) }
                }
                Button("Edytuj aliasy", systemImage: "pencil") { editingAliases = true }
            } header: {
                Text("Aliasy")
            } footer: {
                Text("Alternatywne nazwy, po których wyszukiwarka też znajdzie ćwiczenie.")
            }

            let chain = progression(of: exercise)
            if chain.count > 1 {
                Section("Progresja") {
                    ForEach(chain) { step in
                        if step.id == exercise.id {
                            Label(step.name, systemImage: "largecircle.fill.circle")
                                .fontWeight(.semibold)
                        } else {
                            NavigationLink {
                                ExerciseDetailView(exerciseId: step.id)
                            } label: {
                                Label(step.name, systemImage: isEasier(step, than: exercise, in: chain)
                                      ? "arrow.down.circle" : "arrow.up.circle")
                            }
                        }
                    }
                }
            }

            if !exercise.variants.isEmpty {
                Section("Warianty") {
                    ForEach(exercise.variants, id: \.self) { Text($0) }
                }
            }

            if !exercise.description.isEmpty {
                Section("Opis") { MarkdownText(text: exercise.description) }
            }

            let links = sourceLinks(exercise)
            if !links.isEmpty {
                Section("Źródła") {
                    ForEach(links) { link in
                        Link(destination: link.url) {
                            LabeledContent(link.title, value: link.detail)
                        }
                    }
                }
            }
        }
        .refreshable { await refresh() }
        .toolbar {
            if exercise.isCustom {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Edytuj", systemImage: "pencil") { editing = true }
                        Button("Usuń", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $editing) { ExerciseEditorView(exercise: exercise) }
        .sheet(isPresented: $editingAliases) { AliasesEditorView(exercise: exercise) }
        .alert("Usunąć to ćwiczenie?", isPresented: $confirmDelete) {
            Button("Usuń", role: .destructive) { Task { await delete(exercise) } }
            Button("Anuluj", role: .cancel) {}
        } message: {
            Text("Ćwiczenia użytego w planach lub treningach nie da się usunąć – możesz je zarchiwizować w edycji.")
        }
    }

    private struct SourceLink: Identifiable {
        let url: URL
        let title: String
        let detail: String
        var id: URL { url }
    }

    private func sourceLinks(_ exercise: Exercise) -> [SourceLink] {
        var result: [SourceLink] = exercise.links.compactMap { link in
            URL(string: link.url).map { SourceLink(url: $0, title: link.source, detail: link.type) }
        }
        if let raw = exercise.sourceUrl, let url = URL(string: raw), !result.contains(where: { $0.url == url }) {
            result.append(SourceLink(url: url, title: exercise.source ?? url.host() ?? raw,
                                     detail: exercise.sourceLicense ?? ""))
        }
        var seen = Set<URL>()
        return result.filter { seen.insert($0.url).inserted }
    }

    /// Easier exercises (prev links) first, then this one, then harder (next links).
    private func progression(of exercise: Exercise) -> [Exercise] {
        var easier: [Exercise] = []
        var seen: Set<String> = [exercise.id]
        var cursor = exercise.prevExerciseId
        while let id = cursor, !seen.contains(id), let step = store.byId[id], easier.count < 20 {
            easier.insert(step, at: 0)
            seen.insert(id)
            cursor = step.prevExerciseId
        }
        var harder: [Exercise] = []
        cursor = exercise.nextExerciseId
        while let id = cursor, !seen.contains(id), let step = store.byId[id], harder.count < 20 {
            harder.append(step)
            seen.insert(id)
            cursor = step.nextExerciseId
        }
        return easier + [exercise] + harder
    }

    private func isEasier(_ step: Exercise, than exercise: Exercise, in chain: [Exercise]) -> Bool {
        guard let a = chain.firstIndex(where: { $0.id == step.id }),
              let b = chain.firstIndex(where: { $0.id == exercise.id }) else { return false }
        return a < b
    }

    private func refresh() async {
        await store.loadIfNeeded()
        do {
            store.upsert(try await APIClient.shared.exercise(exerciseId))
            loadError = nil
        } catch {
            if !Task.isCancelled && store.byId[exerciseId] == nil { loadError = error.localizedDescription }
        }
    }

    private func delete(_ exercise: Exercise) async {
        do {
            try await APIClient.shared.deleteExercise(exercise.id)
            deleted += 1
            dismiss()
            store.remove(exercise.id)
        } catch {
            actionError = error.localizedDescription
        }
    }
}

/// Sheet: alternative names of an exercise (library or custom).
struct AliasesEditorView: View {
    let exercise: Exercise

    @Environment(ExerciseStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var aliases: [AliasItem]
    @State private var saving = false
    @State private var error: String?
    @State private var saved = 0

    struct AliasItem: Identifiable, Hashable {
        let id = UUID()
        var text: String
    }

    init(exercise: Exercise) {
        self.exercise = exercise
        _aliases = State(initialValue: exercise.aliases.map { AliasItem(text: $0) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach($aliases) { $alias in
                        TextField("Alias", text: $alias.text)
                            .autocorrectionDisabled()
                    }
                    .onDelete { aliases.remove(atOffsets: $0) }
                    Button("Dodaj alias", systemImage: "plus") { aliases.append(AliasItem(text: "")) }
                        .disabled(aliases.count >= 30)
                } footer: {
                    Text("Do 30 aliasów, każdy do 80 znaków.")
                }
                if let error {
                    Section { ErrorText(message: error) }
                }
            }
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Zapisz") { Task { await save() } }.bold()
                    }
                }
            }
            .sensoryFeedback(.success, trigger: saved)
        }
    }

    private func save() async {
        var unique: [String] = []
        for alias in aliases.map({ $0.text.trimmingCharacters(in: .whitespaces) }) where !alias.isEmpty {
            if !unique.contains(where: { $0.caseInsensitiveCompare(alias) == .orderedSame }) { unique.append(alias) }
        }
        if unique.contains(where: { $0.count > 80 }) {
            error = String(localized: "Alias może mieć najwyżej 80 znaków.")
            return
        }
        saving = true
        error = nil
        defer { saving = false }
        do {
            store.upsert(try await APIClient.shared.saveAliases(unique, exercise: exercise.id))
            saved += 1
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
