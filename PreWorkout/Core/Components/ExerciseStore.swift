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

    /// Datasets the user switched off (stored as "off" so new datasets show up on).
    private(set) var hiddenDatasets: Set<String> {
        didSet { UserDefaults.standard.set(Array(hiddenDatasets).sorted(), forKey: Self.hiddenKey) }
    }

    private static let hiddenKey = "preworkout.exercises.hiddenDatasets"
    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
        hiddenDatasets = Set(UserDefaults.standard.stringArray(forKey: Self.hiddenKey) ?? [])
    }

    // MARK: Datasets

    /// Exercises of the switched-on datasets (lists and pickers use this).
    var enabled: [Exercise] { hiddenDatasets.isEmpty ? all : all.filter(isEnabled) }

    func isEnabledDataset(_ key: String) -> Bool { !hiddenDatasets.contains(key) }

    func isEnabled(_ exercise: Exercise) -> Bool { !hiddenDatasets.contains(ExerciseDataset.key(of: exercise)) }

    /// Datasets present in the library, with how many exercises each has.
    var datasets: [DatasetCount] {
        var counts: [String: Int] = [:]
        for e in all { counts[ExerciseDataset.key(of: e), default: 0] += 1 }
        return counts.keys
            .map { DatasetCount(dataset: ExerciseDataset(key: $0), count: counts[$0] ?? 0) }
            .sorted { $0.dataset.order == $1.dataset.order ? $0.dataset.key < $1.dataset.key : $0.dataset.order < $1.dataset.order }
    }

    func setDataset(_ key: String, enabled: Bool) {
        if enabled { hiddenDatasets.remove(key) } else { hiddenDatasets.insert(key) }
    }

    func loadIfNeeded() async {
        if !loaded, let cached: [Exercise] = DiskCache.read("exercises") {
            set(cached)
            loaded = true
            error = nil
            Task { await load() }
            return
        }
        if !loaded && !isLoading { await load() }
        else if loaded { Task { await load() } }
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

    func reset(clearPreferences: Bool = false) {
        all = []
        byId = [:]
        loaded = false
        error = nil
        if clearPreferences {
            hiddenDatasets = []
        }
    }

    private func set(_ list: [Exercise]) {
        all = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        byId = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }
}

struct DatasetCount: Identifiable {
    let dataset: ExerciseDataset
    let count: Int
    var id: String { dataset.key }
}

/// A source of exercises in the shared library (column `source` on the server).
/// The calisthenics seed merges two Hugging Face datasets, so they are one here.
struct ExerciseDataset: Identifiable, Hashable {
    let key: String
    var id: String { key }

    static func key(of exercise: Exercise) -> String {
        if exercise.isCustom { return "custom" }
        switch exercise.source ?? "" {
        case "martjn", "rafaeljaime", "merged": return "calisthenics"
        case "free-exercise-db": return "gym"
        case "": return "other"
        case let other: return other
        }
    }

    var order: Int {
        switch key {
        case "calisthenics": return 0
        case "gym": return 1
        case "custom": return 2
        default: return 3
        }
    }

    var icon: String {
        switch key {
        case "calisthenics": return "figure.gymnastics"
        case "gym": return "dumbbell"
        case "custom": return "person.crop.circle"
        default: return "square.stack.3d.up"
        }
    }

    var title: String {
        switch key {
        case "calisthenics": return String(localized: "Kalistenika")
        case "gym": return String(localized: "Siłownia")
        case "custom": return String(localized: "Własne ćwiczenia")
        case "other": return String(localized: "Inne")
        default: return key
        }
    }

    var detail: String? {
        switch key {
        case "calisthenics": return String(localized: "Zbiory Martjn i RafaelJaime (Hugging Face)")
        case "gym": return String(localized: "free-exercise-db: siłownia, mobilność, cardio")
        case "custom": return String(localized: "Ćwiczenia dodane przez ciebie")
        default: return nil
        }
    }
}
