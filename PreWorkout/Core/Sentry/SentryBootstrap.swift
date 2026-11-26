import Foundation
import Sentry

/// Starts Sentry once at launch. Events are anonymous and scrubbed of Health/weight data.
enum SentryBootstrap {
    private static let anonymousIdKey = "preworkout.sentry.anonymousUserId"
    private static let sensitiveKeyFragments = [
        "weight", "waga", "healthkit", "bodymass", "body_mass", "body-mass",
        "bmi", "hkquantity", "hkmetadata", "hkunit",
    ]

    static func start() {
        SentrySDK.start { options in
            options.dsn = Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String
            options.sendDefaultPii = false
            options.tracesSampleRate = 0.1
            options.attachScreenshot = false
            options.attachViewHierarchy = false
            options.enableCaptureFailedRequests = false
            options.releaseName = releaseName
            options.environment = environment
            options.beforeSend = { event in
                scrub(event)
                return event
            }
        }
        assignAnonymousUser()
    }

    private static var releaseName: String {
        let id = Bundle.main.bundleIdentifier ?? "preworkout"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(id)@\(version)+\(build)"
    }

    private static var environment: String {
#if DEBUG
        "debug"
#else
        isTestFlight ? "testflight" : "production"
#endif
    }

    private static var isTestFlight: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    private static func assignAnonymousUser() {
        let defaults = UserDefaults.standard
        let id = defaults.string(forKey: anonymousIdKey) ?? {
            let created = UUID().uuidString
            defaults.set(created, forKey: anonymousIdKey)
            return created
        }()
        let user = Sentry.User(userId: id)
        user.email = nil
        user.username = nil
        user.ipAddress = nil
        user.name = nil
        SentrySDK.setUser(user)
    }

    @discardableResult
    private static func scrub(_ event: Event) -> Event {
        if let user = event.user {
            user.email = nil
            user.username = nil
            user.ipAddress = nil
            user.name = nil
            if let data = user.data {
                var cleaned: [String: Any] = [:]
                for (rawKey, value) in data {
                    let key = rawKey as? String ?? String(describing: rawKey)
                    if isSensitiveKey(key) {
                        cleaned[key] = "[redacted]"
                    } else if let text = value as? String, containsSensitive(text) {
                        cleaned[key] = "[redacted]"
                    } else {
                        cleaned[key] = value
                    }
                }
                user.data = cleaned
            }
            event.user = user
        }
        if let extra = event.extra {
            event.extra = scrubDictionary(extra)
        }
        if let tags = event.tags {
            event.tags = scrubStringMap(tags)
        }
        if let context = event.context {
            event.context = scrubDictionary(context) as? [String: [String: Any]]
        }
        if let breadcrumbs = event.breadcrumbs {
            for crumb in breadcrumbs {
                if let message = crumb.message, containsSensitive(message) {
                    crumb.message = "[redacted]"
                }
                if let data = crumb.data {
                    crumb.data = scrubDictionary(data)
                }
            }
        }
        if let request = event.request {
            request.data = nil
            request.cookies = nil
            request.headers = nil
            event.request = request
        }
        if let message = event.message?.formatted, containsSensitive(message) {
            event.message = SentryMessage(formatted: "[redacted]")
        }
        return event
    }

    private static func containsSensitive(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return sensitiveKeyFragments.contains { fragment in lowered.contains(fragment) }
    }

    private static func isSensitiveKey(_ key: String) -> Bool {
        let lowered = key.lowercased()
        return sensitiveKeyFragments.contains { fragment in lowered.contains(fragment) }
    }

    private static func scrubDictionary(_ input: [String: Any]) -> [String: Any] {
        var output: [String: Any] = [:]
        for (key, value) in input {
            if isSensitiveKey(key) {
                output[key] = "[redacted]"
                continue
            }
            if let nested = value as? [String: Any] {
                output[key] = scrubDictionary(nested)
            } else if let list = value as? [Any] {
                output[key] = list.map { item -> Any in
                    if let nested = item as? [String: Any] {
                        return scrubDictionary(nested)
                    }
                    if let text = item as? String, containsSensitive(text) {
                        return "[redacted]"
                    }
                    return item
                }
            } else if let text = value as? String, containsSensitive(text) {
                output[key] = "[redacted]"
            } else {
                output[key] = value
            }
        }
        return output
    }

    private static func scrubStringMap(_ input: [String: String]) -> [String: String] {
        var output: [String: String] = [:]
        for (key, value) in input {
            if isSensitiveKey(key) || containsSensitive(value) {
                output[key] = "[redacted]"
            } else {
                output[key] = value
            }
        }
        return output
    }
}
