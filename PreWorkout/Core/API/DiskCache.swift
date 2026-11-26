import Foundation

/// On-disk JSON cache for API list responses, keyed by user (and person).
/// Shown immediately, then refreshed in the background with If-None-Match.
enum DiskCache {
    struct Key: Hashable {
        var userId: String
        var personId: String?
        var name: String
    }

    private static let folderName = "preworkout-cache"
    private static let currentName = "current-user.txt"

    private static var root: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(folderName, isDirectory: true)
    }

    static func currentUserId() -> String? {
        guard let root, let raw = try? String(contentsOf: root.appendingPathComponent(currentName), encoding: .utf8) else {
            return nil
        }
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? nil : id
    }

    static func setCurrentUser(_ userId: String) {
        guard let root else { return }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? userId.data(using: .utf8)?.write(to: root.appendingPathComponent(currentName), options: .atomic)
    }

    /// Removes every cached response (logout, account deletion, account switch).
    static func clearAll() {
        guard let root else { return }
        try? FileManager.default.removeItem(at: root)
    }

    static func file(for key: Key) -> URL? {
        guard let root else { return nil }
        var dir = root.appendingPathComponent(safe(key.userId), isDirectory: true)
        if let person = key.personId, !person.isEmpty {
            dir = dir.appendingPathComponent(safe(person), isDirectory: true)
        }
        return dir.appendingPathComponent("\(safe(key.name)).json")
    }

    static func readRaw(_ key: Key) -> (etag: String?, data: Data)? {
        guard let url = file(for: key), let blob = try? Data(contentsOf: url),
              let env = try? JSONDecoder().decode(Envelope.self, from: blob) else { return nil }
        return (env.etag, env.data)
    }

    static func read<T: Decodable>(_ key: Key) -> T? {
        guard let raw = readRaw(key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: raw.data)
    }

    static func read<T: Decodable>(_ name: String, person: String? = nil) -> T? {
        guard let userId = currentUserId() else { return nil }
        return read(Key(userId: userId, personId: person, name: name))
    }


    static func writeRaw(_ key: Key, etag: String?, data: Data) {
        guard let url = file(for: key) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let env = Envelope(etag: etag, data: data, savedAt: Date())
        guard let blob = try? JSONEncoder().encode(env) else { return }
        try? blob.write(to: url, options: .atomic)
    }

    static func write<T: Encodable>(_ key: Key, etag: String?, value: T) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        writeRaw(key, etag: etag, data: data)
    }

    static func remove(_ key: Key) {
        guard let url = file(for: key) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func safe(_ raw: String) -> String {
        raw.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }

    private struct Envelope: Codable {
        var etag: String?
        var data: Data
        var savedAt: Date
    }
}
