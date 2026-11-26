import Foundation
import Network
import Observation

extension Notification.Name {
    /// Posted after queued writes reached the server (screens reload).
    static let outboxFlushed = Notification.Name("preworkout.outboxFlushed")
}

enum OutboxKind: String, Codable, Sendable {
    case diary, profile, workout, calendarNote, calendarEntry
}

/// One write that could not be sent (no network) and waits for the connection.
struct OutboxItem: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var kind: OutboxKind
    var personId: String
    /// Same kind + person + key: a later save replaces the pending one.
    var key: String
    var method: String
    var path: String
    var body: Data?
    var createdAt: Date
}

/// What to do with a queued write after the server (or the network) answered.
enum OutboxRules {
    enum Outcome {
        /// Applied (or already applied earlier): remove from the queue.
        case delivered
        /// Network or server trouble: keep, try again later.
        case retry
        /// Session expired: keep, wait for sign-in.
        case unauthorized
        /// Rejected by the server (4xx): drop and tell the user.
        case drop(String)
    }

    static func isNetworkError(_ error: Error) -> Bool {
        if error is URLError { return true }
        return (error as NSError).domain == NSURLErrorDomain
    }

    static func classify(_ error: Error, method: String) -> Outcome {
        if isNetworkError(error) { return .retry }
        switch error {
        case APIError.unauthorized:
            return .unauthorized
        case APIError.http(let status, let message):
            if status == 401 { return .unauthorized }
            if status >= 500 || status == 408 || status == 425 || status == 429 { return .retry }
            // Deleting something that is already gone is a success.
            if status == 404 && method == "DELETE" { return .delivered }
            return .drop(message)
        default:
            return .retry
        }
    }
}

/// Queue file per user, outside Caches so logging out or clearing the cache does not lose writes.
enum OutboxStore {
    private static func file(_ userId: String) -> URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        let dir = base.appendingPathComponent("preworkout-outbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = userId.unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) || $0 == "-" ? String($0) : "_" }
            .joined()
        return dir.appendingPathComponent(safe + ".json")
    }

    static func load(userId: String) -> [OutboxItem] {
        guard let file = file(userId), let data = try? Data(contentsOf: file) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return (try? decoder.decode([OutboxItem].self, from: data)) ?? []
    }

    static func save(_ items: [OutboxItem], userId: String) {
        guard let file = file(userId) else { return }
        if items.isEmpty {
            try? FileManager.default.removeItem(at: file)
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        if let data = try? encoder.encode(items) {
            try? data.write(to: file, options: .atomic)
        }
    }

    /// Removes every queue (account deletion).
    static func removeAll() {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ) else { return }
        try? FileManager.default.removeItem(at: base.appendingPathComponent("preworkout-outbox", isDirectory: true))
    }
}

/// Offline writes, same idea as the web outbox: a write that fails because of the network is kept on disk
/// (per user), shown at once from the cache, and sent in order when the connection is back
/// (network path monitor, app foreground, retry with backoff).
@MainActor @Observable
final class Outbox {
    static let shared = Outbox()

    private(set) var items: [OutboxItem] = []
    private(set) var flushing = false
    /// Message about a change the server rejected (it was dropped from the queue).
    var rejectedMessage: String?

    var pending: Int { items.count }

    @ObservationIgnored private var userId: String?
    @ObservationIgnored private var inFlight: String?
    @ObservationIgnored private var monitor: NWPathMonitor?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var failures = 0

    private init() {}

    /// Starts watching the network and sends what is waiting.
    func start() {
        if monitor == nil {
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { [weak self] path in
                guard path.status == .satisfied else { return }
                Task { @MainActor in self?.networkBack() }
            }
            monitor.start(queue: DispatchQueue(label: "preworkout.outbox.path"))
            self.monitor = monitor
        }
        flush()
    }

    private func networkBack() {
        failures = 0
        flush()
    }

    /// Loads the queue of the signed-in user (the queue is per user).
    private func attach() {
        let current = DiskCache.currentUserId()
        guard current != userId else { return }
        userId = current
        items = current.map { OutboxStore.load(userId: $0) } ?? []
    }

    func hasPending(kind: OutboxKind, person: String, key: String) -> Bool {
        attach()
        return items.contains { $0.kind == kind && $0.personId == person && $0.key == key }
    }

    func enqueue(kind: OutboxKind, person: String, key: String, method: String, path: String, body: Data?) {
        attach()
        guard let userId else { return }
        if let index = items.firstIndex(where: {
            $0.kind == kind && $0.personId == person && $0.key == key && $0.id != inFlight
        }) {
            var existing = items[index]
            if existing.method == "POST" && method == "DELETE" {
                // Created and deleted before it ever reached the server.
                items.remove(at: index)
            } else {
                // A pending create absorbs later edits (same id, full body).
                if !(existing.method == "POST" && method == "PUT") {
                    existing.method = method
                    existing.path = path
                }
                existing.body = body
                items[index] = existing
            }
        } else {
            items.append(OutboxItem(
                id: newId(), kind: kind, personId: person, key: key,
                method: method, path: path, body: body, createdAt: Date()
            ))
        }
        OutboxStore.save(items, userId: userId)
        scheduleRetry()
    }

    func flush() {
        attach()
        guard !flushing, !items.isEmpty, userId != nil else { return }
        retryTask?.cancel()
        flushing = true
        Task { await run() }
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        guard !items.isEmpty else { return }
        let delay = min(60.0, pow(2.0, Double(min(failures, 6))))
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    private func run() async {
        defer { flushing = false }
        guard let userId else { return }
        var finished: [OutboxItem] = []
        var needsRetry = false
        var unauthorized = false
        var rejected: [String] = []

        for item in items.sorted(by: { $0.createdAt < $1.createdAt }) {
            // Replaced or removed since the snapshot: use the current version.
            guard let current = items.first(where: { $0.id == item.id }) else { continue }
            inFlight = current.id
            let outcome: OutboxRules.Outcome
            do {
                try await APIClient.shared.replay(current.method, current.path, body: current.body)
                outcome = .delivered
            } catch {
                outcome = OutboxRules.classify(error, method: current.method)
            }
            inFlight = nil

            var stop = false
            switch outcome {
            case .delivered:
                items.removeAll { $0.id == current.id }
                finished.append(current)
            case .drop(let message):
                items.removeAll { $0.id == current.id }
                finished.append(current)
                rejected.append(message)
            case .retry:
                needsRetry = true
                stop = true
            case .unauthorized:
                unauthorized = true
                stop = true
            }
            if stop { break }
        }

        OutboxStore.save(items, userId: userId)

        if !finished.isEmpty {
            forgetOptimistic(finished, userId: userId)
            NotificationCenter.default.post(name: .outboxFlushed, object: nil)
        }
        if let first = rejected.first {
            rejectedMessage = first
        }
        if needsRetry {
            failures += 1
            scheduleRetry()
        } else {
            failures = 0
            // Writes queued while sending wait for the next round (after sign-in when the session expired).
            if !unauthorized, !items.isEmpty { scheduleRetry() }
        }
    }

    /// The optimistic cache entries are replaced by the server's answer on the next read.
    private func forgetOptimistic(_ finished: [OutboxItem], userId: String) {
        for item in finished {
            let names: [String]
            switch item.kind {
            case .diary: names = ["diary"]
            case .profile: names = ["settings"]
            case .workout:
                let id = item.key.replacingOccurrences(of: "workout:", with: "")
                names = ["workouts", "workout-\(id)"]
            case .calendarNote: names = ["calendar-notes"]
            case .calendarEntry: names = ["calendar-entries"]
            }
            for name in names {
                DiskCache.remove(.init(userId: userId, personId: item.personId, name: name))
            }
        }
    }

    /// Account deletion: nothing may stay behind.
    func discardAll() {
        retryTask?.cancel()
        items = []
        userId = nil
        OutboxStore.removeAll()
    }
}
