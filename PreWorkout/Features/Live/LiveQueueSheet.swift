import SwiftUI

/// Sheet: every exercise of the session. Tap to jump, swipe to skip or
/// remove, hold for order and supersets; add and finish at the bottom.
struct LiveQueueSheet: View {
    let onAdd: (String?) -> Void
    let onFinish: () -> Void

    @Environment(LiveStore.self) private var live
    @Environment(\.dismiss) private var dismiss
    @State private var pendingRemove: Int?

    var body: some View {
        NavigationStack {
            Group {
                if let session = live.session {
                    list(session)
                }
            }
            .navigationTitle("Trening")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Gotowe") { dismiss() } }
            }
        }
        .alert(
            "Usunąć z seriami?",
            isPresented: Binding(get: { pendingRemove != nil }, set: { if !$0 { pendingRemove = nil } }),
            presenting: pendingRemove
        ) { index in
            Button("Usuń", role: .destructive) { live.update { s, _ in s.removeExercise(index) } }
            Button("Anuluj", role: .cancel) {}
        }
        .lvSheet([.medium, .large])
    }

    private func restoreAction(_ index: Int) -> () -> Void {
        {
            live.tap()
            live.update { s, _ in s.restoreExercise(index) }
            dismiss()
        }
    }

    private func list(_ session: LiveSession) -> some View {
        let labels = session.groupLabels
        return List {
            Section {
                ForEach(Array(session.exercises.enumerated()), id: \.element.id) { index, e in
                    QueueRow(
                        exercise: e,
                        name: live.name(of: e),
                        groupLabel: e.item.groupId.flatMap { labels[$0] },
                        isCurrent: index == session.current,
                        onRestore: e.status == .skipped ? restoreAction(index) : nil
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        live.tap()
                        live.update { s, _ in s.goTo(index) }
                        dismiss()
                    }
                    .listRowBackground(index == session.current ? LV.ember.opacity(0.12) : LV.surface)
                    .swipeActions(edge: .trailing) {
                        Button("Usuń", systemImage: "trash") { pendingRemove = index }
                            .tint(LV.danger)
                        if e.isOpen {
                            Button("Pomiń", systemImage: "forward") { live.update { s, _ in s.skipExercise(index) } }
                        } else if e.status == .skipped {
                            Button("Przywróć", systemImage: "arrow.uturn.backward") { live.update { s, _ in s.restoreExercise(index) } }
                        } else {
                            Button("Wróć do niego", systemImage: "arrow.uturn.backward") { live.update { s, _ in s.reopenExercise(index) } }
                        }
                    }
                    .contextMenu {
                        Button("Wyżej", systemImage: "arrow.up") { live.update { s, _ in s.moveExercise(index, by: -1) } }
                            .disabled(index == 0)
                        Button("Niżej", systemImage: "arrow.down") { live.update { s, _ in s.moveExercise(index, by: 1) } }
                            .disabled(index == session.exercises.count - 1)
                        if let g = e.item.groupId {
                            Button("Dodaj do superserii", systemImage: "plus.rectangle.on.rectangle") { onAdd(g) }
                            Button("Wyłącz z superserii", systemImage: "rectangle.badge.minus") { live.update { s, _ in s.ungroup(index) } }
                        }
                        if e.item.sequence.count > 1 {
                            Button("Rozdziel combo", systemImage: "scissors") { live.update { s, _ in s.splitCombo(index) } }
                        }
                        Button("Usuń", systemImage: "trash", role: .destructive) { pendingRemove = index }
                    }
                }
            } footer: {
                Text("Dotknij, aby przejść. Przytrzymaj, aby zmienić kolejność lub superserię.")
            }
            Section {
                Button { onAdd(nil) } label: {
                    Label("Dodaj ćwiczenie", systemImage: "plus").foregroundStyle(LV.text)
                }
                .listRowBackground(LV.surface)
            }
            Section {
                LVCta(mood: .done, height: 52) { onFinish() } content: {
                    Image(systemName: "flag.checkered")
                    Text("Zakończ trening")
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
    }
}

private struct QueueRow: View {
    let exercise: LiveExercise
    let name: String
    let groupLabel: String?
    let isCurrent: Bool
    var onRestore: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if let groupLabel {
                        LVBadge(text: Text("Superseria \(groupLabel)"), colors: [LV.violet, LV.flame])
                    }
                    Text(verbatim: name)
                        .font(.system(size: 16, weight: isCurrent ? .bold : .regular))
                        .foregroundStyle(exercise.status == .skipped ? LV.faint : LV.text)
                        .lineLimit(2)
                }
                Text(verbatim: exercise.item.isSession
                     ? (exercise.status == .done ? SessionFormat.summary(exercise.item) : String(localized: "Sesja"))
                     : "\(exercise.item.sets.count) / \(max(exercise.plannedSets, exercise.item.sets.count))")
                    .font(.system(size: 13))
                    .foregroundStyle(LV.muted)
                    .monospacedDigit()
            }
            Spacer()
            if let onRestore {
                Button(action: onRestore) {
                    Label("Przywróć", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(LV.ember.opacity(0.18), in: Capsule())
                        .foregroundStyle(LV.text)
                }
                .buttonStyle(.borderless)
            } else if isCurrent {
                Text("Teraz").lvCaps(LV.ember)
            }
        }
        .padding(.vertical, 2)
    }

    private var icon: String {
        switch exercise.status {
        case .done: return "checkmark.circle.fill"
        case .skipped: return "forward.circle"
        case .active: return "play.circle.fill"
        case .pending: return isCurrent ? "play.circle" : "circle"
        }
    }

    private var color: Color {
        switch exercise.status {
        case .done: return LV.lime
        case .skipped: return LV.faint
        default: return isCurrent ? LV.ember : LV.muted
        }
    }
}
