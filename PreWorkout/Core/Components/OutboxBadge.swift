import SwiftUI

/// Small note above the tab bar while changes made offline wait to be sent.
struct OutboxBadge: View {
    private let outbox = Outbox.shared

    var body: some View {
        if outbox.pending > 0 {
            Button {
                outbox.flush()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: outbox.flushing ? "arrow.triangle.2.circlepath" : "icloud.slash")
                    Text("Oczekuje na synchronizację: \(outbox.pending)")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.thinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
            .accessibilityHint("Dotknij, aby spróbować teraz")
        }
    }
}

extension View {
    func outboxBadge() -> some View {
        modifier(OutboxBadgeInset())
    }
}

/// Only insets when something is queued. A permanent empty bottom inset can
/// confuse TabView and leave the tab bar stuck hidden after heavy navigation.
private struct OutboxBadgeInset: ViewModifier {
    private let outbox = Outbox.shared

    func body(content: Content) -> some View {
        if outbox.pending > 0 {
            content.safeAreaInset(edge: .bottom, spacing: 0) { OutboxBadge() }
        } else {
            content
        }
    }
}
