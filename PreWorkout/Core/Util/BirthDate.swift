import Foundation

/// Birth date as the server stores it (ISO `yyyy-MM-dd`) and the age derived from it.
/// The server accepts ages from 10 to 100.
enum BirthDate {
    static let minAge = 10
    static let maxAge = 100

    private static var calendar: Calendar { Calendar(identifier: .gregorian) }

    /// Parses `yyyy-MM-dd`; nil for anything that is not a real calendar date.
    static func date(from iso: String) -> Date? {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard iso.count == 10, parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        guard let date = calendar.date(from: components) else { return nil }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        guard back.year == year, back.month == month, back.day == day else { return nil }
        return date
    }

    static func iso(from date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Whole years from the birth date to `now`; nil when `iso` is not a real date.
    static func age(from iso: String, now: Date = .now) -> Int? {
        guard let birth = date(from: iso) else { return nil }
        let b = calendar.dateComponents([.year, .month, .day], from: birth)
        let t = calendar.dateComponents([.year, .month, .day], from: now)
        guard let by = b.year, let bm = b.month, let bd = b.day,
              let ty = t.year, let tm = t.month, let td = t.day else { return nil }
        var years = ty - by
        if tm < bm || (tm == bm && td < bd) { years -= 1 }
        return years
    }

    /// Age from the birth date when it is real, not in the future and 10–100 years ago.
    static func validAge(from iso: String, now: Date = .now) -> Int? {
        guard let date = date(from: iso), date <= now, let age = age(from: iso, now: now),
              (minAge...maxAge).contains(age) else { return nil }
        return age
    }

    /// Dates the picker offers: from 100 years ago to 10 years ago.
    static func pickerRange(now: Date = .now) -> ClosedRange<Date> {
        let lower = calendar.date(byAdding: .year, value: -(maxAge + 1), to: now) ?? now
        let upper = calendar.date(byAdding: .year, value: -minAge, to: now) ?? now
        return (calendar.date(byAdding: .day, value: 1, to: lower) ?? lower)...upper
    }

    /// Where the picker starts when no date is set yet.
    static func defaultDate(now: Date = .now) -> Date {
        calendar.date(byAdding: .year, value: -25, to: now) ?? now
    }

    /// A legacy free-text age, only when it is a whole number from 10 to 100.
    static func legacyAge(_ raw: String) -> Int? {
        guard let value = Int(raw.trimmingCharacters(in: .whitespaces)),
              (minAge...maxAge).contains(value) else { return nil }
        return value
    }
}

extension UserSettings {
    /// Age in years: from the birth date, else a sane legacy age; nil when unknown.
    var effectiveAge: Int? {
        if let birthDate, let age = BirthDate.validAge(from: birthDate) { return age }
        return BirthDate.legacyAge(age)
    }
}

extension Person {
    var effectiveAge: Int? {
        if let birthDate, let age = BirthDate.validAge(from: birthDate) { return age }
        return BirthDate.legacyAge(age)
    }
}
