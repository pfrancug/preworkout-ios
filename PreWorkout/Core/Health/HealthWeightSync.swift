import Foundation
import HealthKit

/// Visible steps of a two-way Health body-weight sync.
struct HealthSyncProgress: Equatable {
    enum Phase: Equatable {
        case reading
        case importing
        case writing
        case done
    }

    var phase: Phase
    var done: Int
    var total: Int

    var fraction: Double {
        guard total > 0 else { return phase == .done ? 1 : 0 }
        return Double(done) / Double(total)
    }
}

/// Two-way body-weight sync with Apple Health. Diary remains the source of truth
/// in PreWorkout; Health samples we wrote are tagged so they are not imported twice.
@MainActor
@Observable
final class HealthWeightSync {
    static let isAvailable = HKHealthStore.isHealthDataAvailable()

    private static let prefix = "preworkout.fit.weight."
    private static let kg = HKUnit.gramUnit(with: .kilo)
    private static let type = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
    private static let batchSize = 100

    private let store = HKHealthStore()

    var lastError: String?
    var busy = false
    var progress: HealthSyncProgress?

    var canShare: Bool {
        guard Self.isAvailable else { return false }
        return store.authorizationStatus(for: Self.type) == .sharingAuthorized
    }

    static func syncIdentifier(person: String, day: String) -> String {
        prefix + person + "." + day
    }

    func requestAccess() async -> Bool {
        guard Self.isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [Self.type], read: [Self.type])
            return canShare
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Import Health samples we did not write, then write app-entered weigh-ins back to Health.
    func synchronize(person: String, rows: [DiaryRow]) async -> [DiaryRow] {
        guard Self.isAvailable else { return rows }
        busy = true
        lastError = nil
        progress = HealthSyncProgress(phase: .reading, done: 0, total: 0)
        defer { busy = false }
        do {
            let samples = try await loadSamples()
            var updated = rows
            let patches = importForeign(samples, into: &updated)
            if !patches.isEmpty {
                try await upload(patches, person: person)
                updated = try await APIClient.shared.diary(person: person)
            }
            if canShare {
                try await pushDiary(updated, person: person, existing: samples)
            }
            let finishedTotal = max(progress?.total ?? 0, patches.count)
            progress = HealthSyncProgress(
                phase: .done,
                done: finishedTotal,
                total: finishedTotal
            )
            return updated
        } catch {
            lastError = error.localizedDescription
            progress = nil
            return rows
        }
    }

    func write(_ row: DiaryRow, person: String) async {
        guard canShare, row.source == .app, let kg = row.appWeight ?? row.weight, kg > 0 else { return }
        let day = String(row.date.prefix(10))
        guard let sample = quantitySample(kg: kg, day: day, person: person) else { return }
        do {
            try await store.save(sample)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func delete(day: String, person: String) async {
        guard canShare, let date = DayString.date(from: day) else { return }
        do {
            let samples = try await loadSamples()
            let id = Self.syncIdentifier(person: person, day: day)
            let ours = samples.filter {
                ($0.metadata?[HKMetadataKeySyncIdentifier] as? String) == id
            }
            if !ours.isEmpty {
                try await store.delete(ours)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Private

    private func loadSamples() async throws -> [HKQuantitySample] {
        try await withCheckedThrowingContinuation { cont in
            let query = HKSampleQuery(
                sampleType: Self.type,
                predicate: nil,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, results, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                cont.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            store.execute(query)
        }
    }

    private func importForeign(_ samples: [HKQuantitySample], into rows: inout [DiaryRow]) -> [DiaryWeightPatch] {
        var byDay: [String: Double] = [:]
        for sample in samples {
            if let identifier = sample.metadata?[HKMetadataKeySyncIdentifier] as? String,
               identifier.hasPrefix(Self.prefix) {
                continue
            }
            let day = DayString.string(from: sample.startDate)
            byDay[day] = sample.quantity.doubleValue(for: Self.kg)
        }

        var patches: [DiaryWeightPatch] = []
        for (day, kg) in byDay where kg > 0 {
            if let existing = rows.filter({ String($0.date.prefix(10)) == day && $0.hasAnyWeight })
                .max(by: { $0.id < $1.id }) {
                if let imported = existing.importedWeight, abs(imported - kg) < 0.05 {
                    continue
                }
                let protectApp =
                    existing.hasAppWeight && abs((existing.appWeight ?? 0) - kg) >= 0.05
                var next = existing
                next.healthWeight = kg
                if !protectApp {
                    next.source = .health
                    if !existing.hasAppWeight {
                        next.weight = kg
                    }
                }
                if let index = rows.firstIndex(where: { $0.id == existing.id && $0.date == existing.date }) {
                    rows[index] = next
                }
                patches.append(
                    DiaryWeightPatch(
                        id: existing.id > 0 ? existing.id : nil,
                        date: day,
                        weight: protectApp ? nil : kg,
                        source: .health,
                        healthWeight: kg,
                        includeWeight: !protectApp,
                        includeHealthWeight: true
                    )
                )
            } else {
                let next = DiaryRow(id: 0, date: day, weight: kg, source: .health, healthWeight: kg)
                rows.append(next)
                patches.append(
                    DiaryWeightPatch(
                        id: nil,
                        date: day,
                        weight: kg,
                        source: .health,
                        healthWeight: kg,
                        includeWeight: true,
                        includeHealthWeight: true
                    )
                )
            }
        }
        return patches
    }

    private func upload(_ patches: [DiaryWeightPatch], person: String) async throws {
        let total = patches.count
        progress = HealthSyncProgress(phase: .importing, done: 0, total: total)
        await Task.yield()
        var done = 0
        var index = 0
        while index < patches.count {
            let end = min(index + Self.batchSize, patches.count)
            _ = try await APIClient.shared.upsertDiaryWeights(
                Array(patches[index..<end]),
                person: person
            )
            done = end
            progress = HealthSyncProgress(phase: .importing, done: done, total: total)
            await Task.yield()
            index = end
        }
    }

    private func pushDiary(_ rows: [DiaryRow], person: String, existing: [HKQuantitySample]) async throws {
        let known = existing.reduce(into: [String: HKQuantitySample]()) { result, sample in
            if let identifier = sample.metadata?[HKMetadataKeySyncIdentifier] as? String {
                result[identifier] = sample
            }
        }
        var pending: [HKQuantitySample] = []
        for row in rows where row.source == .app {
            guard let kg = row.appWeight ?? row.weight, kg > 0 else { continue }
            let day = String(row.date.prefix(10))
            let identifier = Self.syncIdentifier(person: person, day: day)
            if let already = known[identifier], abs(already.quantity.doubleValue(for: Self.kg) - kg) < 0.05 {
                continue
            }
            if let sample = quantitySample(kg: kg, day: day, person: person) {
                pending.append(sample)
            }
        }
        guard !pending.isEmpty else { return }
        let total = pending.count
        progress = HealthSyncProgress(phase: .writing, done: 0, total: total)
        await Task.yield()
        var index = 0
        while index < pending.count {
            let end = min(index + Self.batchSize, pending.count)
            let chunk: [HKObject] = Array(pending[index..<end])
            try await store.save(chunk)
            progress = HealthSyncProgress(phase: .writing, done: end, total: total)
            await Task.yield()
            index = end
        }
    }

    private func quantitySample(kg: Double, day: String, person: String) -> HKQuantitySample? {
        guard let date = DayString.date(from: day) else { return nil }
        let quantity = HKQuantity(unit: Self.kg, doubleValue: kg)
        return HKQuantitySample(
            type: Self.type,
            quantity: quantity,
            start: date,
            end: date,
            metadata: [
                HKMetadataKeySyncIdentifier: Self.syncIdentifier(person: person, day: day),
                HKMetadataKeySyncVersion: NSNumber(value: 1),
            ]
        )
    }
}
