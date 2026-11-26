import Foundation
import TelemetryDeck

/// Anonymous product analytics via TelemetryDeck.
/// Disabled in Debug and when the App ID is empty. Never send names, emails, or Health/weight values.
/// TestFlight builds are marked testMode so their signals show only when the
/// TelemetryDeck dashboard Test Mode toggle is on.
enum Analytics {
    private static let flag = Flag()
    private static let firstOpenKey = "preworkout.analytics.firstOpenRecorded"

    static func start() {
#if DEBUG
        return
#else
        let appID = plist("TelemetryDeckAppID")
        guard !appID.isEmpty else { return }
        // SDK 2.x sends to /v2/ unless a namespace is set. The dashboard app
        // uses TelemetryDeckNamespace from Info.plist; without it, signals
        // never appear even with Test Mode on.
        let namespace = plist("TelemetryDeckNamespace")
        var config = TelemetryDeck.Config(
            appID: appID,
            namespace: namespace.isEmpty ? nil : namespace
        )
        // Release TestFlight builds would otherwise be treated as production.
        config.testMode = isTestFlight
        TelemetryDeck.initialize(config: config)
        flag.set()
        recordFirstOpenIfNeeded()
#endif
    }

    static func send(_ name: String, _ parameters: [String: String] = [:]) {
#if DEBUG
        return
#else
        guard flag.isSet else { return }
        TelemetryDeck.signal(name, parameters: parameters)
#endif
    }

    static func countBucket(_ count: Int) -> String {
        switch count {
        case ...0: return "0"
        case 1: return "1"
        case 2...5: return "2-5"
        case 6...20: return "6-20"
        case 21...50: return "21-50"
        case 51...100: return "51-100"
        default: return "100+"
        }
    }

    static func durationBucket(seconds: Double) -> String {
        let minutes = seconds / 60
        switch minutes {
        case ..<15: return "<15m"
        case 15..<30: return "15-30m"
        case 30..<60: return "30-60m"
        case 60..<90: return "60-90m"
        default: return "90m+"
        }
    }

    static func exerciseCountBucket(_ count: Int) -> String {
        switch count {
        case ...0: return "0"
        case 1: return "1"
        case 2...3: return "2-3"
        case 4...6: return "4-6"
        case 7...10: return "7-10"
        default: return "11+"
        }
    }

    static func queryLengthBucket(_ count: Int) -> String {
        switch count {
        case ...0: return "0"
        case 1...2: return "1-2"
        case 3...5: return "3-5"
        case 6...10: return "6-10"
        case 11...20: return "11-20"
        case 21...40: return "21-40"
        default: return "40+"
        }
    }

    /// Lowercased, trimmed search text, capped at 40 characters. Used only for
    /// zero-result exercise searches (missing-library signal, not personal data).
    static func normalizedSearchQuery(_ query: String) -> String {
        String(query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().prefix(40))
    }

    /// Once per install. Existing installs (session, person, or saved tab) are
    /// marked without sending, so an upgrade is not counted as a first open.
    private static func recordFirstOpenIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: firstOpenKey) == nil else { return }
        defaults.set(true, forKey: firstOpenKey)
        let existingInstall =
            KeychainToken.get() != nil
            || !(defaults.string(forKey: "preworkout.activePersonId") ?? "").isEmpty
            || defaults.object(forKey: "preworkout.tab") != nil
            || defaults.object(forKey: "preworkout.live.defaultRest") != nil
        guard !existingInstall else { return }
        send("App.firstOpen")
        send("Onboarding.stepViewed", ["step": "firstOpen"])
    }

    private static var isTestFlight: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    private static func plist(_ key: String) -> String {
        let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        func set() {
            lock.lock()
            value = true
            lock.unlock()
        }

        var isSet: Bool {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }
}
