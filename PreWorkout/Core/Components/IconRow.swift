import SwiftUI

/// Label of every list row: tinted icon, primary title.
struct IconLabel: View {
    let title: LocalizedStringKey
    let icon: String

    init(_ title: LocalizedStringKey, icon: String) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        Label {
            Text(title)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(.tint)
        }
    }
}

/// The one row style of list screens: tinted icon, primary title, optional secondary value.
/// Use inside a NavigationLink/Button for a tappable row; `external` adds a link arrow.
struct IconRow: View {
    let title: LocalizedStringKey
    let icon: String
    var value: String?
    var external = false
    var badge = false

    init(_ title: LocalizedStringKey, icon: String, value: String? = nil, external: Bool = false, badge: Bool = false) {
        self.title = title
        self.icon = icon
        self.value = value
        self.external = external
        self.badge = badge
    }

    var body: some View {
        LabeledContent {
            if external {
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            } else if badge {
                Circle().fill(Color.red).frame(width: 9, height: 9)
                    .accessibilityHidden(true)
            } else if let value {
                Text(value)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
        } label: {
            IconLabel(title, icon: icon)
        }
    }
}
