import Foundation
import SwiftUI

/// Sane bounds for every number the user can type, and for numbers read back
/// from the server, the cache or the offline queue. Keep the server limits
/// (`server/validation` in the web repo) at least as wide as these.
struct NumericLimit: Sendable, Equatable {
    let min: Double
    let max: Double
    var unit = ""

    func contains(_ value: Double) -> Bool {
        value.isFinite && value >= min && value <= max
    }

    /// Value inside the range; NaN / ±∞ fall back to the lower bound.
    func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return min }
        return Swift.min(max, Swift.max(min, value))
    }

    /// Digits before the decimal separator that can still fit under `max`.
    var maxIntegerDigits: Int { String(max.safeInt).count }

    /// "20–500 kg"
    var rangeText: String {
        let core = "\(min.short(2))–\(max.short(2))"
        return unit.isEmpty ? core : "\(core) \(unit)"
    }

    /// User-facing message for a value outside the range.
    var message: String {
        String(localized: "Wartość musi być w zakresie \(rangeText).")
    }
}

enum Limits {
    static let bodyWeightKg = NumericLimit(min: 20, max: 500, unit: "kg")
    static let heightCm = NumericLimit(min: 50, max: 300, unit: "cm")
    static let ageYears = NumericLimit(min: 1, max: 120)
    static let goalKcal = NumericLimit(min: 0, max: 20_000, unit: "kcal")
    static let goalMacroGrams = NumericLimit(min: 0, max: 2_000, unit: "g")

    static let reps = NumericLimit(min: 0, max: 1_000)
    static let attempts = NumericLimit(min: 0, max: 1_000)
    static let loadKg = NumericLimit(min: 0, max: 1_000, unit: "kg")
    static let distanceM = NumericLimit(min: 0, max: 500_000, unit: "m")
    static let rpe = NumericLimit(min: 0, max: 10)
    static let rir = NumericLimit(min: 0, max: 10)
    static let sessionMinutes = NumericLimit(min: 0, max: 1_440, unit: "min")
    static let durationSeconds = NumericLimit(min: 0, max: 86_400)
    static let restSeconds = NumericLimit(min: 0, max: 7_200)
    static let plannedSets = NumericLimit(min: 1, max: 100)

    /// Anything else typed into a numeric field.
    static let generic = NumericLimit(min: 0, max: 1_000_000)

    /// Longest text typed into free-form fields (titles, notes).
    static let titleLength = 200
    static let noteLength = 5_000
}

extension Double {
    /// Rounded to a whole number without ever trapping: NaN / ±∞ become 0,
    /// huge values are clamped to ±1e15.
    var safeInt: Int {
        guard isFinite else { return 0 }
        let limit = 1e15
        return Int(Swift.min(limit, Swift.max(-limit, rounded())))
    }

    /// Whole seconds from a duration of any magnitude (see `safeInt`).
    var safeSeconds: Int { Swift.max(0, safeInt) }

    /// nil for NaN / ±∞.
    var finiteOrNil: Double? { isFinite ? self : nil }
}

extension Optional where Wrapped == Double {
    /// nil unless finite and inside `limit` (decoded server / cache data).
    func within(_ limit: NumericLimit) -> Double? {
        guard let value = self, limit.contains(value) else { return nil }
        return value
    }
}

extension String {
    /// At most `count` characters (typed free text).
    func capped(_ count: Int) -> String { String(prefix(count)) }
}

extension Limits {
    /// Profile texts from the server or an old cache: kept only when sane, otherwise "" (not set).
    static func cleanAge(_ raw: String) -> String {
        guard let value = Int(raw.trimmingCharacters(in: .whitespaces)), ageYears.contains(Double(value)) else { return "" }
        return raw
    }

    static func cleanHeight(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard Double(text).within(heightCm) != nil else { return "" }
        return raw
    }

    static func cleanWeight(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard Double(text).within(bodyWeightKg) != nil else { return "" }
        return raw
    }
}

extension KeyedDecodingContainer {
    /// Number that is nil (instead of a decoding error) when missing, mistyped,
    /// non-finite or outside `limit`: bad server / cache data must not break a screen.
    func lenientDouble(_ key: Key, _ limit: NumericLimit) -> Double? {
        guard let value = try? decodeIfPresent(Double.self, forKey: key) else { return nil }
        return value.within(limit)
    }

    func lenientInt(_ key: Key, _ limit: NumericLimit) -> Int? {
        lenientDouble(key, limit).map(\.safeInt)
    }
}

extension View {
    /// Cuts typed text to `count` characters.
    func maxLength(_ text: Binding<String>, _ count: Int) -> some View {
        onChange(of: text.wrappedValue) { _, value in
            if value.count > count { text.wrappedValue = value.capped(count) }
        }
    }
}
