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

    /// "listopad 2026" style month label (section headers).
    static func month(_ day: String) -> String {
        guard let date = date(from: day) else { return String(day.prefix(7)) }
        return date.formatted(.dateTime.month(.wide).year())
    }

    /// Full weekday and date, e.g. "środa, 18 listopada".
    static func dayLong(_ day: String) -> String {
        guard let date = date(from: day) else { return day }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    /// Weekday + date, e.g. "śr., 18 lis".
    static func short(_ day: String) -> String {
        guard let date = date(from: day) else { return day }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

extension Double {
    /// Up to `digits` fraction digits in the current locale.
    func short(_ digits: Int = 1) -> String {
        formatted(.number.precision(.fractionLength(0...digits)))
    }
}

extension Optional where Wrapped == Double {
    /// "–" for nil, otherwise up to `digits` fraction digits.
    func display(_ digits: Int = 1, unit: String = "") -> String {
        guard let value = self else { return "–" }
        let text = value.short(digits)
        return unit.isEmpty ? text : "\(text) \(unit)"
    }
}

/// "0:45", "1:30", "1:05:03" (see `DurationText`).
func durationText(seconds: Double) -> String { DurationText.format(seconds) }

enum SetFormat {
    /// Compact one-line description of a logged set, e.g. "8 powt. · +10 kg · RPE 8".
    static func summary(_ set: WorkoutSet) -> String {
        var parts: [String] = []
        if let stepped = set.stepsSummary {
            parts.append(stepped)
        } else if let reps = set.reps {
            parts.append(String(localized: "\(reps) powt."))
        }
        if set.stepsSummary == nil, let hold = set.holdSeconds { parts.append(durationText(seconds: hold)) }
        if let distance = set.distanceM { parts.append("\(distance.short()) m") }
        if set.stepsSummary == nil, let duration = set.durationSeconds { parts.append(durationText(seconds: Double(duration))) }
        if let weight = set.weightKg, weight > 0 { parts.append("+\(weight.short(2)) kg") }
        if set.assistance != "none" {
            let note = set.assistanceNote.trimmingCharacters(in: .whitespaces)
            let name = String(localized: Labels.assistance(set.assistance))
            parts.append(note.isEmpty ? name : "\(name) (\(note))")
        }
        if let rpe = set.rpe { parts.append("RPE \(rpe.short())") }
        if let rir = set.rir { parts.append("RIR \(rir)") }
        if let rest = set.restSeconds { parts.append(String(localized: "przerwa \(durationText(seconds: Double(rest)))")) }
        return parts.isEmpty ? "–" : parts.joined(separator: " · ")
    }
}


enum SessionFormat {
    /// "Sesja · 40:00 · 12 prób" for a session/block entry.
    static func summary(_ item: WorkoutExercise) -> String {
        let set = item.sets.first
        var parts = [String(localized: "Sesja"), DurationText.format(set?.durationSeconds ?? 0)]
        if let n = set?.attempts, n > 0 { parts.append(attempts(n)) }
        let note = (set?.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = item.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { parts.append(note) }
        else if !fallback.isEmpty { parts.append(fallback) }
        return parts.joined(separator: " · ")
    }

    static func attempts(_ n: Int) -> String {
        let mod10 = n % 10
        let mod100 = n % 100
        if n == 1 { return String(localized: "1 próba") }
        if (12...14).contains(mod100) { return String(localized: "\(n) prób") }
        if (2...4).contains(mod10) { return String(localized: "\(n) próby") }
        return String(localized: "\(n) prób")
    }
}
