import Foundation
import Observation

/// Remembers the last version whose notes the user has seen and decides on
/// launch: big news → a small sheet once; only small fixes → a dot on
/// Profile › What's new; fresh install → nothing.
@MainActor
@Observable
final class WhatsNewStore {
    static let shared = WhatsNewStore()

    private static let lastSeenKey = "preworkout.whatsNew.lastSeen"
    /// Installs from before this feature (0.1.5 or older) count as having seen 0.1.5.
    private static let legacyBaseline = "0.1.5"

    var showSheet = false
    private var checked = false
    private(set) var hasUnseen = false
    private(set) var highlights: [ChangelogItem] = []

    /// Released versions (not newer than this build), newest first.
    var released: [ChangelogEntry] {
        Changelog.entries.filter { !AppVersion.less(AppVersion.current, $0.version) }
    }

    func checkOnLaunch() {
        guard !checked else { return }
        checked = true
        let defaults = UserDefaults.standard
        let current = AppVersion.current
        guard let lastSeen = defaults.string(forKey: Self.lastSeenKey) ?? Self.existingInstallBaseline() else {
            // Fresh install: nothing to announce.
            defaults.set(current, forKey: Self.lastSeenKey)
            return
        }
        let unseen = released.filter { AppVersion.less(lastSeen, $0.version) }
        guard !unseen.isEmpty else {
            defaults.set(current, forKey: Self.lastSeenKey)
            return
        }
        hasUnseen = true
        highlights = Array(unseen.flatMap { $0.items.filter(\.highlight) }.prefix(4))
        if !highlights.isEmpty {
            showSheet = true
            // Shown once: the dot also goes away.
            markSeen()
        }
    }

    /// Opening the sheet or the full list counts as seen.
    func markSeen() {
        UserDefaults.standard.set(AppVersion.current, forKey: Self.lastSeenKey)
        hasUnseen = false
    }

    /// An install from before this feature already has app data (tab choice,
    /// sign-in token); a fresh install has none.
    private static func existingInstallBaseline() -> String? {
        let defaults = UserDefaults.standard
        let hadData = defaults.object(forKey: "preworkout.tab") != nil || KeychainToken.get() != nil
        return hadData ? legacyBaseline : nil
    }
}
