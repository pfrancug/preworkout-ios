import Foundation
import SwiftUI

// Shapes mirror `ICalendarEntry` / `ICalendarNotes` in the web app's `shared/types.ts`.

/// A calendar activity (a category such as "Run", or a custom one) on a day.
struct CalendarEntry: Codable, Identifiable, Hashable {
    let id: String
    /// "activity" (category) or "custom"
    var type: String
    var activityId: String?
    var name: String?
    var icon: String?
    var color: String?
    /// HH:mm, nil = all day
    var time: String?
    var timeEnd: String?
    var note: String?
}

/// `GET /calendar/entries`: date (YYYY-MM-DD) -> entry id -> entry.
typealias CalendarEntries = [String: [String: CalendarEntry]]

/// Body of `POST /calendar/entries` (`entry` part); nil keys are omitted.
struct CalendarEntryInput: Encodable {
    var type: String
    var activityId: String?
    var name: String?
    var icon: String?
    var color: String?
    var time: String?
    var timeEnd: String?
    var note: String?
}

/// Body of `PATCH /calendar/entries/:id`; time and timeEnd are sent as null to clear them.
struct CalendarEntryPatch: Encodable {
    var note: String
    var time: String?
    var timeEnd: String?

    private enum CodingKeys: String, CodingKey { case note, time, timeEnd }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(note, forKey: .note)
        try c.encode(time, forKey: .time)
        try c.encode(timeEnd, forKey: .timeEnd)
    }
}

/// One line of the calendar: a logged workout or another activity.
struct CalendarItem: Identifiable, Hashable {
    let id: String
    let date: String
    let title: String
    let symbol: String
    let colorId: String?
    let time: String?
    let timeEnd: String?
    let note: String?
    let workout: WorkoutSummary?
    let entry: CalendarEntry?

    var color: Color { ActivityStyle.color(colorId) }

    var timeText: String? {
        guard let time else { return nil }
        if let timeEnd, !timeEnd.isEmpty { return time + " – " + timeEnd }
        return time
    }
}

/// "HH:mm" strings of the calendar API <-> Date (time of day only).
enum TimeText {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "HH:mm"
        return f
    }()

    static func string(from date: Date) -> String { formatter.string(from: date) }

    /// Today at the given HH:mm; falls back to `fallback` for unparsable text.
    static func date(from text: String?, fallback: Date = Date()) -> Date {
        guard let text, let parsed = formatter.date(from: text) else { return fallback }
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute], from: parsed)
        return calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: Date()) ?? fallback
    }
}
