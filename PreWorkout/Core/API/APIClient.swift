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
/// Auth = the same signed httpOnly cookie the web app uses (`POST /api/auth/login`);
/// URLSession keeps it in the shared cookie storage (valid 180 days).
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
    private func raw(_ method: String, _ path: String, body: Data? = nil) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: try url(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
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
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? decoder.decode(ErrorBody.self, from: data))?.error
                ?? "\(method) \(path) failed (\(http.statusCode))"
            throw APIError.http(status: http.statusCode, message: message)
        }
        return (data, http)
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    func get<T: Decodable>(_ path: String) async throws -> T {
        let (data, _) = try await raw("GET", path)
        return try decode(data)
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

