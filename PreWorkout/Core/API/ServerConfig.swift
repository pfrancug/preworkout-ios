import Foundation

/// API server address. Never committed: CI injects the build setting
/// `API_BASE_URL` (Info.plist `APIBaseURL`) from a repository secret. It can be
/// overridden on the sign-in screen; without either the user must enter it.
enum ServerConfig {
    private static let overrideKey = "preworkout.serverURL"

    static var bundledURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String else { return nil }
        return parse(raw)
    }

    static var baseURL: URL? {
        if let raw = UserDefaults.standard.string(forKey: overrideKey), let url = parse(raw) {
            return url
        }
        return bundledURL
    }

    static func setOverride(_ url: URL?) {
        if let url {
            UserDefaults.standard.set(url.absoluteString, forKey: overrideKey)
        } else {
            UserDefaults.standard.removeObject(forKey: overrideKey)
        }
    }

    /// Accepts only absolute http(s) addresses.
    static func parse(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", url.host() != nil else { return nil }
        return url
    }
}
