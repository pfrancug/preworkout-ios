import Foundation
import HealthKit

/// Two-way body-weight sync with Apple Health. Diary remains the source of truth
/// in PreWorkout; Health samples we wrote are tagged so they are not imported twice.
@MainActor
@Observable
final class HealthWeightSync {
    static let isAvailable = HKHealthStore.isHealthDataAvailable()

    private static let prefix = "preworkout.fit.weight."
    private static let kg = HKUnit.gramUnit(with: .kilo)
    private static let type = HKQuantityType.quantityType(forIdentifier: .bodyMass)!

    private let store = HKHealthStore()

    var lastError: String?
    var busy = false

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

    /// Import Health samples we did not write, then write every diary weigh-in back to Health.
    func synchronize(person: String, rows: [DiaryRow]) async -> [DiaryRow] {
        guard Self.isAvailable else { return rows }
        busy = true
        lastError = nil
        defer { busy = false }
        do {
            let samples = try await loadSamples()
            var updated = rows
            let imported = importForeign(samples, into: &updated)
            for row in imported {
                _ = try await APIClient.shared.upsertDiaryWeight(
                    date: String(row.date.prefix(10)),
                    weight: row.weight ?? 0,
                    id: row.id > 0 ? row.id : nil,
                    person: person
                )
            }
            if !imported.isEmpty {
                updated = try await APIClient.shared.diary(person: person)
            }
            if canShare {
                try await pushDiary(updated, person: person, existing: samples)
            }
            return updated
        } catch {
            lastError = error.localizedDescription
            return rows
        }
    }

    func write(_ row: DiaryRow, person: String) async {
        guard canShare, let kg = row.weight, kg > 0 else { return }
        let day = String(row.date.prefix(10))
        guard let date = DayString.date(from: day) else { return }
        do {
            let quantity = HKQuantity(unit: Self.kg, doubleValue: kg)
            let sample = HKQuantitySample(
                type: Self.type,
                quantity: quantity,
                start: date,
                end: date,
                metadata: [
                    HKMetadataKeySyncIdentifier: Self.syncIdentifier(person: person, day: day),
                    HKMetadataKeySyncVersion: NSNumber(value: 1),
                ]
            )
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
                    || Calendar.current.isDate($0.startDate, inSameDayAs: date)
                    && $0.metadata?[HKMetadataKeySyncIdentifier] as? String == id
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

    private func importForeign(_ samples: [HKQuantitySample], into rows: inout [DiaryRow]) -> [DiaryRow] {
        var byDay: [String: Double] = [:]
        for sample in samples {
            if let identifier = sample.metadata?[HKMetadataKeySyncIdentifier] as? String,
               identifier.hasPrefix(Self.prefix) {
                continue
            }
            let day = DayString.string(from: sample.startDate)
            byDay[day] = sample.quantity.doubleValue(for: Self.kg)
        }

        var imported: [DiaryRow] = []
        for (day, kg) in byDay where kg > 0 {
            if let existing = rows.filter({ String($0.date.prefix(10)) == day && ($0.weight ?? 0) > 0 })
                .max(by: { $0.id < $1.id }) {
                if abs((existing.weight ?? 0) - kg) < 0.05 {
                    continue
                }
                let next = DiaryRow(id: existing.id, date: day, weight: kg)
                if let index = rows.firstIndex(where: { $0.id == existing.id }) {
                    rows[index] = next
                }
                imported.append(next)
            } else {
                let next = DiaryRow(id: 0, date: day, weight: kg)
                rows.append(next)
                imported.append(next)
            }
        }
        return imported
    }

    private func pushDiary(_ rows: [DiaryRow], person: String, existing: [HKQuantitySample]) async throws {
        let known = Set(
            existing.compactMap { sample -> String? in
                sample.metadata?[HKMetadataKeySyncIdentifier] as? String
            }
        )
        for row in rows {
            guard let kg = row.weight, kg > 0 else { continue }
            let day = String(row.date.prefix(10))
            let identifier = Self.syncIdentifier(person: person, day: day)
            // Same identifier + same version updates in place if Health already has it.
            if known.contains(identifier) {
                let already = existing.last {
                    ($0.metadata?[HKMetadataKeySyncIdentifier] as? String) == identifier
                }
                if let already, abs(already.quantity.doubleValue(for: Self.kg) - kg) < 0.05 {
                    continue
                }
            }
            await write(row, person: person)
        }
    }
}
