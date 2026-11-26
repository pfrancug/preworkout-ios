import SwiftUI

/// Row with a label and a right-aligned whole-number field (empty = nil).
/// Input is limited to `limit`: digits beyond its maximum are refused with a
/// message, and a value below its minimum is flagged under the row.
struct IntField: View {
    let title: LocalizedStringKey
    @Binding var value: Int?
    var unit: String?
    var limit: NumericLimit
    @State private var refused = false
    @FocusState private var focused: Bool

    init(_ title: LocalizedStringKey, value: Binding<Int?>, unit: String? = nil, limit: NumericLimit = Limits.generic) {
        self.title = title
        _value = value
        self.unit = unit
        self.limit = limit
    }

    private var showError: Bool {
        if refused { return true }
        guard !focused, let value else { return false }
        return !limit.contains(Double(value))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) {
                HStack(spacing: 4) {
                    TextField("–", text: Binding(
                        get: { value.map(String.init) ?? "" },
                        set: { raw in
                            let digits = String(raw.filter { $0.isASCII && $0.isNumber }.prefix(limit.maxIntegerDigits))
                            guard let parsed = Int(digits) else {
                                value = nil
                                refused = false
                                return
                            }
                            if Double(parsed) > limit.max {
                                refused = true
                            } else {
                                refused = false
                                value = parsed
                            }
                        }
                    ))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focused)
                    if let unit { Text(unit).foregroundStyle(.secondary) }
                }
            }
            if showError {
                Text(limit.message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }
}

/// Row with a label and a right-aligned decimal field (accepts "," and ".").
/// Same limits behaviour as `IntField`; at most two decimals.
struct DecimalField: View {
    let title: LocalizedStringKey
    @Binding var value: Double?
    var unit: String?
    var limit: NumericLimit
    @State private var text = ""
    @State private var refused = false
    @FocusState private var focused: Bool

    init(_ title: LocalizedStringKey, value: Binding<Double?>, unit: String? = nil, limit: NumericLimit = Limits.generic) {
        self.title = title
        _value = value
        self.unit = unit
        self.limit = limit
    }

    private var showError: Bool {
        if refused { return true }
        guard !focused, let value else { return false }
        return !limit.contains(value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) {
                HStack(spacing: 4) {
                    TextField("–", text: $text)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($focused)
                        .onChange(of: text) { oldValue, newValue in
                            let cleaned = Self.sanitize(newValue, limit: limit)
                            let parsed = Self.parse(cleaned)
                            if let parsed, parsed > limit.max {
                                refused = true
                                text = Self.sanitize(oldValue, limit: limit)
                                return
                            }
                            refused = false
                            if cleaned != newValue { text = cleaned }
                            if parsed != value { value = parsed }
                        }
                    if let unit { Text(unit).foregroundStyle(.secondary) }
                }
            }
            if showError {
                Text(limit.message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .onAppear { text = Self.format(value) }
        .onChange(of: value) { _, newValue in
            if Self.parse(text) != newValue { text = Self.format(newValue) }
        }
    }

    /// Digits and one separator only, capped to the integer digits of the limit and two decimals.
    static func sanitize(_ raw: String, limit: NumericLimit) -> String {
        var integer = "", fraction = "", separator: Character?
        for ch in raw {
            if ch.isASCII && ch.isNumber {
                if separator == nil {
                    if integer.count < limit.maxIntegerDigits { integer.append(ch) }
                } else if fraction.count < 2 {
                    fraction.append(ch)
                }
            } else if (ch == "." || ch == ","), separator == nil {
                separator = ch
            }
        }
        guard let separator else { return integer }
        return integer + String(separator) + fraction
    }

    /// nil for empty or unparsable text; never NaN or infinite.
    static func parse(_ raw: String) -> Double? {
        let cleaned = raw.replacingOccurrences(of: ",", with: ".").filter { ($0.isASCII && $0.isNumber) || $0 == "." }
        guard !cleaned.isEmpty, let number = Double(cleaned), number.isFinite else { return nil }
        return number
    }

    static func format(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "" }
        return value.short(2)
    }
}
extension Binding where Value == String? {
    /// Treats "" as nil (nullable text fields of the API).
    var orEmpty: Binding<String> {
        Binding<String>(
            get: { wrappedValue ?? "" },
            set: { wrappedValue = $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        )
    }
}

/// Inline error / info footer used by forms.
struct ErrorText: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
            .font(.footnote)
    }
}

/// Small rounded tag (e.g. "Aktywny", "Własne").
struct Tag: View {
    let text: Text
    var color: Color = .accentColor

    init(_ key: LocalizedStringKey, color: Color = .accentColor) {
        text = Text(key)
        self.color = color
    }

    init(resource: LocalizedStringResource, color: Color = .accentColor) {
        text = Text(resource)
        self.color = color
    }

    var body: some View {
        text
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}
