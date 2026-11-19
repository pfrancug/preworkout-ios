import SwiftUI

struct DiaryView: View {
    @Environment(AppState.self) private var appState
    @State private var state: LoadState<[DiaryRow]> = .idle

    var body: some View {
        NavigationStack {
            LoadStateView(state: state, retry: load) { rows in
                if rows.isEmpty {
                    ContentUnavailableView("Brak wpisów", systemImage: "book")
                } else {
                    List(rows) { row in
                        DiaryRowView(row: row)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Dziennik")
            .toolbar {
                // Editing waits for a per-row diary endpoint (see README milestones).
                ToolbarItem(placement: .primaryAction) {
                    Button("Dodaj", systemImage: "plus") {}.disabled(true)
                }
            }
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private func load() async {
        if case .loaded = state {} else { state = .loading }
        do {
            let rows = try await APIClient.shared.diary(person: appState.activePersonId)
            state = .loaded(rows.sorted { $0.date > $1.date })
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

private struct DiaryRowView: View {
    let row: DiaryRow

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(DayString.label(row.date)).font(.subheadline.weight(.medium))
                Text("B \(row.protein.display(0)) · T \(row.fat.display(0)) · W \(row.carbs.display(0))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(row.weight.display(1, unit: "kg")).monospacedDigit()
                Text(row.kcal.display(0, unit: "kcal")).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            if row.completed == true {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
    }
}
