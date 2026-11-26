import Foundation

extension Notification.Name {
    /// Posted when the server answers 401 outside `/auth/*` (session expired).
    static let apiUnauthorized = Notification.Name("preworkout.apiUnauthorized")
}

enum APIError: LocalizedError {
    case unauthorized
    case http(status: Int, message: String)
    case invalidResponse
    case decoding(String)
    case noServer

    var errorDescription: String? {
        switch self {
        case .unauthorized: return String(localized: "Sesja wygasła, zaloguj się ponownie.")
        case .http(_, let message): return message
        case .invalidResponse: return String(localized: "Nieprawidłowa odpowiedź serwera.")
        case .decoding(let detail): return String(localized: "Błąd danych: \(detail)")
        case .noServer: return String(localized: "Podaj adres serwera.")
        }
    }
}

private struct ErrorBody: Decodable { let error: String? }
private struct Empty: Encodable {}

/// JSON client for the PreWorkout Hono API (`/api/*`).
/// Auth = Keychain Bearer token from Sign in with Apple (`POST /api/auth/apple/native`);
/// the shared cookie storage stays active during the transition from `APP_PASSWORD`.
final class APIClient: @unchecked Sendable {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = .shared
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    private func url(_ path: String) throws -> URL {
        // `path` starts with "/" and may carry a query string.
        guard let base = ServerConfig.baseURL,
              let url = URL(string: "api" + path, relativeTo: base.appendingPathComponent("")) else {
            throw APIError.noServer
        }
        return url.absoluteURL
    }

    @discardableResult
    private func raw(_ method: String, _ path: String, body: Data? = nil, etag: String? = nil) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: try url(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = KeychainToken.get() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        if http.statusCode == 401 {
            if !path.hasPrefix("/auth/") {
                NotificationCenter.default.post(name: .apiUnauthorized, object: nil)
            }
            let message = (try? decoder.decode(ErrorBody.self, from: data))?.error
            throw message.map { APIError.http(status: 401, message: $0) } ?? APIError.unauthorized
        }
        if http.statusCode == 304 { return (data, http) }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? decoder.decode(ErrorBody.self, from: data))?.error
                ?? "\(method) \(path) failed (\(http.statusCode))"
            throw APIError.http(status: http.statusCode, message: message)
        }
        return (data, http)
    }

    func clearSessionCookies() {
        let storage = session.configuration.httpCookieStorage ?? .shared
        for cookie in storage.cookies ?? [] where cookie.name == "pw_session" {
            storage.deleteCookie(cookie)
        }
    }

    func decode<T: Decodable>(_ data: Data) throws -> T {
        // An empty body is read as JSON `null`, so optional results decode to nil.
        let data = data.isEmpty ? Data("null".utf8) : data
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    func get<T: Decodable>(_ path: String, cache cacheKey: DiskCache.Key? = nil) async throws -> T {
        let cached = cacheKey.flatMap { DiskCache.readRaw($0) }
        do {
            let (data, http) = try await raw("GET", path, etag: cached?.etag)
            if http.statusCode == 304, let cached {
                return try decode(cached.data)
            }
            if let cacheKey {
                DiskCache.writeRaw(cacheKey, etag: http.value(forHTTPHeaderField: "ETag"), data: data)
            }
            return try decode(data)
        } catch {
            if let cached, isRetryable(error) { return try decode(cached.data) }
            throw error
        }
    }

    /// Network failures can fall back to a cached body; auth errors must not.
    private func isRetryable(_ error: Error) -> Bool {
        if case APIError.unauthorized = error { return false }
        if case APIError.http(let status, _) = error, status == 401 { return false }
        return true
    }

    func encodeBody<B: Encodable>(_ body: B) throws -> Data {
        try encoder.encode(body)
    }

    /// Sends a write kept in the offline outbox.
    func replay(_ method: String, _ path: String, body: Data?) async throws {
        try await raw(method, path, body: body)
    }

    /// A write that waits in the outbox when the network is down. Returns the response body when it
    /// was sent, nil when it was queued (the caller then shows the change from the cache).
    /// A pending write of the same thing is replaced instead of overtaken.
    func writeOrQueue(
        _ method: String,
        _ path: String,
        body: Data?,
        kind: OutboxKind,
        key: String,
        person: String
    ) async throws -> Data? {
        if await Outbox.shared.hasPending(kind: kind, person: person, key: key) {
            await Outbox.shared.enqueue(kind: kind, person: person, key: key, method: method, path: path, body: body)
            await Outbox.shared.flush()
            return nil
        }
        do {
            let (data, _) = try await raw(method, path, body: body)
            return data
        } catch {
            guard OutboxRules.isNetworkError(error) else { throw error }
            await Outbox.shared.enqueue(kind: kind, person: person, key: key, method: method, path: path, body: body)
            return nil
        }
    }

    func send<T: Decodable, B: Encodable>(_ method: String, _ path: String, body: B) async throws -> T {
        let (data, _) = try await raw(method, path, body: try encoder.encode(body))
        return try decode(data)
    }

    /// Write without a response body (the API answers 204).
    func sendNoContent<B: Encodable>(_ method: String, _ path: String, body: B) async throws {
        try await raw(method, path, body: try encoder.encode(body))
    }

    func sendNoContent(_ method: String, _ path: String) async throws {
        try await raw(method, path)
    }
}

/// Percent-encodes one path segment (ids are server/client generated strings).
func seg(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? value
}

