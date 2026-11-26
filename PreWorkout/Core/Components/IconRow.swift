import SwiftUI

/// The one row style of list screens: tinted icon, primary title, optional secondary value.
/// Use inside a NavigationLink/Button for a tappable row; `external` adds a link arrow.
struct IconRow: View {
    let title: LocalizedStringKey
    let icon: String
    var value: String?
    var external = false

    init(_ title: LocalizedStringKey, icon: String, value: String? = nil, external: Bool = false) {
        self.title = title
        self.icon = icon
        self.value = value
        self.external = external
    }

    var body: some View {
        LabeledContent {
            if external {
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            } else if let value {
                Text(value)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
        } label: {
            Label {
                Text(title)
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(.tint)
            }
        }
    }
}
