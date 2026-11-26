import Foundation
import HealthKit
import UIKit

extension Notification.Name {
    /// Posted when a Health weight sync finishes, pauses, or imports a batch (screens reload diary rows).
    static let healthSyncDidUpdate = Notification.Name("preworkout.healthSyncDidUpdate")
}

/// Visible steps of a two-way Health body-weight sync.
struct HealthSyncProgress: Equatable {
    enum Phase: Equatable {
        case reading
        case resuming
        case importing
        case writing
        case paused
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

/// Dates already sent in a Health import that was interrupted (app backgrounded or dropped connection).
private struct HealthSyncCheckpoint: Codable {
    var person: String
    var uploadedDates: [String]
    var importFinished: Bool
    var total: Int
}

private enum HealthSyncCheckpointStore {
    private static func file(person: String) -> URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        let dir = base.appendingPathComponent("preworkout-healthsync", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let user = DiskCache.currentUserId() ?? "unknown"
        return dir.appendingPathComponent(safe(user) + "." + safe(person) + ".json")
    }

    private static func safe(_ value: String) -> String {
        value.unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) || $0 == "-" ? String($0) : "_" }
            .joined()
    }

    static func load(person: String) -> HealthSyncCheckpoint? {
        guard let file = file(person: person), let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(HealthSyncCheckpoint.self, from: data)
    }

    static func save(_ checkpoint: HealthSyncCheckpoint) {
        guard let file = file(person: checkpoint.person) else { return }
        try? JSONEncoder().encode(checkpoint).write(to: file, options: .atomic)
    }

    static func clear(person: String) {
        guard let file = file(person: person) else { return }
        try? FileManager.default.removeItem(at: file)
    }
}

/// Thrown when a sync is paused because the app left the foreground or background time ran out.
private struct SyncPausedError: Error {}

/// Two-way body-weight sync with Apple Health. Diary remains the source of truth
/// in PreWorkout; Health samples we wrote are tagged so they are not imported twice.
@MainActor
@Observable
final class HealthWeightSync {
    static let shared = HealthWeightSync()
    static let isAvailable = HKHealthStore.isHealthDataAvailable()

    private static let prefix = "preworkout.fit.weight."
    private static let kg = HKUnit.gramUnit(with: .kilo)
    private static let type = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
    private static let batchSize = 100
    private static let retryDelays: [UInt64] = [400_000_000, 800_000_000, 1_600_000_000]

    private let store = HKHealthStore()
    private var inFlight: Task<[DiaryRow], Never>?
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    private var expireFlag = false

    var lastError: String?
    var busy = false
    var progress: HealthSyncProgress?

    var canShare: Bool {
        guard Self.isAvailable else { return false }
        return store.authorizationStatus(for: Self.type) == .sharingAuthorized
    }

    var hasPendingCheckpoint: Bool {
        !busy && progress?.phase == .paused
    }

    static func syncIdentifier(person: String, day: String) -> String {
        prefix + person + "." + day
    }

    func requestAccess() async -> Bool {
        guard Self.isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [Self.type], read: [Self.type])
            reportPermission(samples: try? await loadSamples())
            return canShare
        } catch {
            lastError = error.localizedDescription
            reportPermission(samples: nil)
            return false
        }
    }

    /// HealthKit does not expose read-authorization status. `authorizationStatus`
    /// only reflects write (share) access, so `result` is the share status
    /// (granted / denied / notDetermined). `hasSamples` is whether a body-mass
    /// query returned any samples after the prompt — empty can mean the user
    /// denied read access *or* simply has no weight data in Health.
    private func reportPermission(samples: [HKQuantitySample]?) {
        let result: String
        switch store.authorizationStatus(for: Self.type) {
        case .sharingAuthorized: result = "granted"
        case .sharingDenied: result = "denied"
        case .notDetermined: result = "notDetermined"
        @unknown default: result = "notDetermined"
        }
        let hasSamples: String
        if let samples {
            hasSamples = samples.isEmpty ? "false" : "true"
        } else {
            hasSamples = "unknown"
        }
        Analytics.send("HealthSync.permission", [
            "result": result,
            "hasSamples": hasSamples,
        ])
    }

    /// Resume an interrupted import when the app returns to the foreground.
    func resumeIfNeeded(person: String) async {
        guard Self.isAvailable, !person.isEmpty else { return }
        guard inFlight == nil, HealthSyncCheckpointStore.load(person: person) != nil else { return }
        let rows = (try? await APIClient.shared.diary(person: person)) ?? []
        _ = await synchronize(person: person, rows: rows)
    }

    /// Import Health samples we did not write, then write app-entered weigh-ins back to Health.
    func synchronize(person: String, rows: [DiaryRow]) async -> [DiaryRow] {
        if let current = inFlight {
            return await current.value
        }
        let task = Task { await self.performSynchronize(person: person, rows: rows) }
        inFlight = task
        let result = await task.value
        if inFlight != nil { inFlight = nil }
        return result
    }

    // MARK: Private — run

    private func performSynchronize(person: String, rows: [DiaryRow]) async -> [DiaryRow] {
        guard Self.isAvailable else { return rows }
        busy = true
        lastError = nil
        expireFlag = false
        let bg = startBackgroundTask()
        defer {
            busy = false
            endBackgroundTaskIfNeeded(bg)
        }

        let checkpoint = HealthSyncCheckpointStore.load(person: person)
        var uploaded = Set(checkpoint?.uploadedDates ?? [])
        var importFinished = checkpoint?.importFinished ?? false
        let resuming = checkpoint != nil
        var result = rows
        var plannedTotal = max(checkpoint?.total ?? 0, uploaded.count)

        if resuming {
            progress = HealthSyncProgress(
                phase: .resuming,
                done: uploaded.count,
                total: plannedTotal
            )
        } else {
            progress = HealthSyncProgress(phase: .reading, done: 0, total: 0)
            Analytics.send("HealthSync.started")
        }

        do {
            let samples = try await loadSamples()
            try checkStop()
            var patches = importForeign(samples, into: &result)
            if !uploaded.isEmpty {
                patches.removeAll { uploaded.contains($0.date) }
            }
            plannedTotal = max(plannedTotal, patches.count + uploaded.count)

            if !importFinished && (!patches.isEmpty || !uploaded.isEmpty) {
                persist(person: person, uploaded: uploaded, importFinished: false, total: plannedTotal)
                if !patches.isEmpty {
                    try await upload(
                        patches,
                        person: person,
                        uploaded: &uploaded,
                        total: plannedTotal
                    )
                }
                result = try await retrying {
                    try await APIClient.shared.diary(person: person)
                }
                importFinished = true
                persist(person: person, uploaded: uploaded, importFinished: true, total: plannedTotal)
            } else if importFinished {
                result = try await retrying {
                    try await APIClient.shared.diary(person: person)
                }
            }

            if canShare {
                try await pushDiary(result, person: person, existing: samples)
            }

            HealthSyncCheckpointStore.clear(person: person)
            let finishedTotal = max(plannedTotal, progress?.total ?? 0)
            progress = HealthSyncProgress(phase: .done, done: finishedTotal, total: finishedTotal)
            Analytics.send("HealthSync.finished", ["count": Analytics.countBucket(finishedTotal)])
            notifyUpdated()
            return result
        } catch is CancellationError {
            pause(person: person, uploaded: uploaded, importFinished: importFinished, total: plannedTotal)
            return result
        } catch is SyncPausedError {
            pause(person: person, uploaded: uploaded, importFinished: importFinished, total: plannedTotal)
            return result
        } catch {
            if expireFlag || !isInForeground {
                pause(person: person, uploaded: uploaded, importFinished: importFinished, total: plannedTotal)
                return result
            }
            if !uploaded.isEmpty || checkpoint != nil {
                persist(person: person, uploaded: uploaded, importFinished: checkpoint?.importFinished ?? false, total: plannedTotal)
            }
            lastError = error.localizedDescription
            progress = nil
            return result
        }
    }

    private func pause(person: String, uploaded: Set<String>, importFinished: Bool, total: Int) {
        persist(person: person, uploaded: uploaded, importFinished: importFinished, total: total)
        progress = HealthSyncProgress(phase: .paused, done: uploaded.count, total: max(total, uploaded.count))
        lastError = nil
        notifyUpdated()
    }

    private func persist(person: String, uploaded: Set<String>, importFinished: Bool, total: Int) {
        HealthSyncCheckpointStore.save(
            HealthSyncCheckpoint(
                person: person,
                uploadedDates: uploaded.sorted(),
                importFinished: importFinished,
                total: total
            )
        )
    }

    private func notifyUpdated() {
        NotificationCenter.default.post(name: .healthSyncDidUpdate, object: nil)
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
        guard canShare, DayString.date(from: day) != nil else { return }
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

    private func upload(
        _ patches: [DiaryWeightPatch],
        person: String,
        uploaded: inout Set<String>,
        total: Int
    ) async throws {
        progress = HealthSyncProgress(phase: .importing, done: uploaded.count, total: total)
        await Task.yield()
        var index = 0
        while index < patches.count {
            try checkStop()
            let end = min(index + Self.batchSize, patches.count)
            let chunk = Array(patches[index..<end])
            try await retrying {
                _ = try await APIClient.shared.upsertDiaryWeights(chunk, person: person)
            }
            for patch in chunk {
                uploaded.insert(patch.date)
            }
            persist(person: person, uploaded: uploaded, importFinished: false, total: total)
            progress = HealthSyncProgress(phase: .importing, done: uploaded.count, total: total)
            notifyUpdated()
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
            try checkStop()
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

    // MARK: Background, retry, errors

    private var isInForeground: Bool {
        UIApplication.shared.applicationState == .active
    }

    private func checkStop() throws {
        if expireFlag || Task.isCancelled { throw CancellationError() }
    }

    private func startBackgroundTask() -> UIBackgroundTaskIdentifier {
        expireFlag = false
        if backgroundTask != .invalid {
            endBackgroundTaskIfNeeded(backgroundTask)
        }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "HealthWeightSync") { [weak self] in
            guard let self else { return }
            self.expireFlag = true
            self.inFlight?.cancel()
            self.endBackgroundTaskIfNeeded(self.backgroundTask)
        }
        return backgroundTask
    }

    private func endBackgroundTaskIfNeeded(_ id: UIBackgroundTaskIdentifier) {
        if id != .invalid {
            UIApplication.shared.endBackgroundTask(id)
        }
        if backgroundTask == id {
            backgroundTask = .invalid
        }
    }

    private func retrying<T>(_ op: () async throws -> T) async throws -> T {
        var lastError: Error?
        for attempt in 1...3 {
            try checkStop()
            do {
                return try await op()
            } catch let error as CancellationError {
                throw error
            } catch {
                lastError = error
                if !Self.isTransient(error) { throw error }
                if attempt < 3 {
                    try await Task.sleep(nanoseconds: Self.retryDelays[attempt - 1])
                }
            }
        }
        if expireFlag || Task.isCancelled || !isInForeground {
            throw SyncPausedError()
        }
        throw lastError!
    }

    /// Network drops from backgrounding, timeouts, and a locked Turso write (503 / SQLITE_BUSY).
    static func isTransient(_ error: Error) -> Bool {
        if let url = error as? URLError {
            switch url.code {
            case .networkConnectionLost, .timedOut, .notConnectedToInternet,
                 .dataNotAllowed, .internationalRoamingOff, .callIsActive,
                 .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return true
            default:
                break
            }
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNetworkConnectionLost,
                 NSURLErrorTimedOut,
                 NSURLErrorNotConnectedToInternet,
                 NSURLErrorDataNotAllowed,
                 NSURLErrorInternationalRoamingOff,
                 NSURLErrorCallIsActive,
                 NSURLErrorCannotFindHost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorDNSLookupFailed:
                return true
            default:
                break
            }
        }
        if case APIError.http(let status, let message) = error {
            if status == 503 || status == 429 || status == 408 || status == 425 {
                return true
            }
            if status >= 500 {
                let lower = message.lowercased()
                if lower.contains("sqlite_busy")
                    || lower.contains("database is locked")
                    || lower.contains("hrana stream") {
                    return true
                }
            }
        }
        return false
    }
}
