import Foundation
import TelemetryDeck

/// Anonymous product analytics via TelemetryDeck.
/// Disabled in Debug and when the App ID is empty. Never send names, emails, or Health/weight values.
enum Analytics {
    private static let flag = Flag()

    static func start() {
#if DEBUG
        return
#else
        let appID = plist("TelemetryDeckAppID")
        guard !appID.isEmpty else { return }
        var config = TelemetryDeck.Config(appID: appID)
        // The namespace is stored in Info.plist (`TelemetryDeckNamespace`) for SDK 3,
        // which requires it. This 2.x SDK has no namespace parameter.
        config.testMode = isTestFlight
        TelemetryDeck.initialize(config: config)
        flag.set()
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
        case ...0: "0"
        case 1: "1"
        case 2...5: "2-5"
        case 6...20: "6-20"
        case 21...50: "21-50"
        case 51...100: "51-100"
        default: "100+"
        }
    }

    static func durationBucket(seconds: Double) -> String {
        let minutes = seconds / 60
        switch minutes {
        case ..<15: "<15m"
        case 15..<30: "15-30m"
        case 30..<60: "30-60m"
        case 60..<90: "60-90m"
        default: "90m+"
        }
    }

    static func exerciseCountBucket(_ count: Int) -> String {
        switch count {
        case ...0: "0"
        case 1: "1"
        case 2...3: "2-3"
        case 4...6: "4-6"
        case 7...10: "7-10"
        default: "11+"
        }
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
