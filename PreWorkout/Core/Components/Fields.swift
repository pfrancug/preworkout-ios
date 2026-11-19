import SwiftUI

/// Row with a label and a right-aligned whole-number field (empty = nil).
struct IntField: View {
    let title: LocalizedStringKey
    @Binding var value: Int?
    var unit: String?

    init(_ title: LocalizedStringKey, value: Binding<Int?>, unit: String? = nil) {
        self.title = title
        _value = value
        self.unit = unit
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField("–", text: Binding(
                    get: { value.map(String.init) ?? "" },
                    set: { value = Int($0.filter(\.isNumber)) }
                ))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                if let unit { Text(unit).foregroundStyle(.secondary) }
            }
        }
    }
}

/// Row with a label and a right-aligned decimal field (accepts "," and ".").
struct DecimalField: View {
    let title: LocalizedStringKey
    @Binding var value: Double?
    var unit: String?
    @State private var text = ""

    init(_ title: LocalizedStringKey, value: Binding<Double?>, unit: String? = nil) {
        self.title = title
        _value = value
        self.unit = unit
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField("–", text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: text) { _, newValue in
                        let parsed = Self.parse(newValue)
                        if parsed != value { value = parsed }
                    }
                if let unit { Text(unit).foregroundStyle(.secondary) }
            }
        }
        .onAppear { text = Self.format(value) }
        .onChange(of: value) { _, newValue in
            if Self.parse(text) != newValue { text = Self.format(newValue) }
        }
    }

    static func parse(_ raw: String) -> Double? {
        let cleaned = raw.replacingOccurrences(of: ",", with: ".").filter { $0.isNumber || $0 == "." }
        return cleaned.isEmpty ? nil : Double(cleaned)
    }

    static func format(_ value: Double?) -> String {
        guard let value else { return "" }
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
