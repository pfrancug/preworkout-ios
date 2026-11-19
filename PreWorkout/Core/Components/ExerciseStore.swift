import Foundation
import Observation

/// The shared exercise library (`GET /api/exercises`), loaded once and kept in
/// memory for names, filters and pickers.
@MainActor
@Observable
final class ExerciseStore {
    private(set) var all: [Exercise] = []
    private(set) var byId: [String: Exercise] = [:]
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var loaded = false

    private let api: APIClient

    init(api: APIClient = .shared) { self.api = api }

    func loadIfNeeded() async {
        if !loaded && !isLoading { await load() }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            set(try await api.exercises())
            error = nil
            loaded = true
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    func name(_ id: String) -> String { byId[id]?.name ?? id }

    func upsert(_ exercise: Exercise) {
        var list = all.filter { $0.id != exercise.id }
        list.append(exercise)
        set(list)
    }

    func remove(_ id: String) { set(all.filter { $0.id != id }) }

    private func set(_ list: [Exercise]) {
        all = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        byId = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }
}
