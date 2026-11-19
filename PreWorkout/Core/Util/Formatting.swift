import Foundation

enum DayString {
    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Today as YYYY-MM-DD in the phone's time zone.
    static var today: String { parser.string(from: Date()) }

    static func string(from date: Date) -> String { parser.string(from: date) }
    static func date(from day: String) -> Date? { parser.date(from: day) }

    /// "18 lis 2026" style label for a YYYY-MM-DD string.
    static func label(_ day: String) -> String {
        guard let date = date(from: day) else { return day }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

extension Optional where Wrapped == Double {
    /// "–" for nil, otherwise up to `digits` fraction digits.
    func display(_ digits: Int = 1, unit: String = "") -> String {
        guard let value = self else { return "–" }
        let text = value.formatted(.number.precision(.fractionLength(0...digits)))
        return unit.isEmpty ? text : "\(text) \(unit)"
    }
}
