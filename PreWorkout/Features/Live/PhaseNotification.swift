import Foundation
import UserNotifications

/// One-shot local notification at an absolute date. Used for a set
/// countdown today, and meant to be reused for interval phase changes.
enum PhaseNotification {
    static let setTimerId = "preworkout.phase-timer"
    static let restId = "preworkout.rest"

    /// Schedules a notification at `end`. Cancels a previous request with
    /// the same `id` first. No-ops (and cancels) when `end` is nil or
    /// within one second of now.
    @MainActor
    static func schedule(id: String, at end: Date?, title: String, body: String, sound: Bool) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard let end, end.timeIntervalSinceNow > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound ? .default : nil
        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: end
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    @MainActor
    static func cancel(id: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }
}

/// Suppresses countdown / rest banners while the app is in the foreground:
/// the in-app ticker already plays the sound and haptic.
final class ForegroundNotificationSilencer: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        []
    }
}
