import Charts
import SwiftUI

/// Weight history: chart, add/edit, and two-way Apple Health sync.
struct WeightView: View {
    @Environment(AppState.self) private var appState
    @State private var rows: [DiaryRow] = []
    @State private var range: WeightRange = .days90
    @State private var editor: WeightEditor?
    @State private var pendingDelete: DiaryRow?
    @State private var error: String?
    @State private var health = HealthWeightSync()
    @State private var loaded = false

    private var weighIns: [DiaryRow] {
        rows.filter { ($0.weight ?? 0) > 0 }
            .sorted { $0.date < $1.date }
    }

    private var visible: [DiaryRow] {
        guard let start = range.startDate else { return weighIns }
        let key = DayString.string(from: start)
        return weighIns.filter { $0.date >= key }
    }

    var body: some View {
        List {
            Section {
                Picker("Zakres", selection: $range) {
                    ForEach(WeightRange.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                chart
            }

            if HealthWeightSync.isAvailable {
                Section {
                    if health.canShare {
                        Button {
                            Task { await syncHealth() }
                        } label: {
                            HStack {
                                Label("Synchronizuj z Health", systemImage: "heart")
                                if health.busy {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(health.busy)
                    } else {
                        Button {
                            Task { await connectHealth() }
                        } label: {
                            Label("Połącz z Apple Health", systemImage: "heart")
                        }
                        .disabled(health.busy)
                    }
                } footer: {
                    Text("Waga jest synchronizowana z aplikacją Health w obie strony. Dane z Health nie są nikomu udostępniane i nie służą do reklam.")
                }
            }

            Section {
                if weighIns.isEmpty {
                    Text("Brak pomiarów wagi")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(weighIns.reversed()) { row in
                        Button {
                            editor = WeightEditor(row: row)
                        } label: {
                            HStack {
                                Text(DayString.label(String(row.date.prefix(10))))
                                Spacer()
                                Text(verbatim: "\((row.weight ?? 0).short()) kg")
                                    .monospacedDigit()
                                    .foregroundStyle(.primary)
                            }
                        }
                        .foregroundStyle(.primary)
                        .swipeActions {
                            Button("Usuń", systemImage: "trash", role: .destructive) {
                                pendingDelete = row
                            }
                        }
                    }
                }
            } header: {
                Text("Pomiary")
            }
        }
        .navigationTitle("Waga")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Dodaj wagę", systemImage: "plus") {
                    editor = WeightEditor(row: nil)
                }
            }
        }
        .sheet(item: $editor) { item in
            WeightEditorSheet(editor: item) { date, weight, id in
                await save(date: date, weight: weight, id: id)
            }
        }
        .alert(
            "Usunąć ten pomiar?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { row in
            Button("Usuń", role: .destructive) { Task { await delete(row) } }
            Button("Anuluj", role: .cancel) {}
        } message: { _ in
            Text("Tej operacji nie można cofnąć.")
        }
        .alert("Błąd", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
        .task {
            if !loaded { await load() }
        }
        .refreshable { await load(sync: true) }
        .onChange(of: health.lastError) { _, newValue in
            if let newValue { error = newValue }
        }
    }

    @ViewBuilder
    private var chart: some View {
        if visible.count >= 2 {
            Chart(visible) { row in
                LineMark(
                    x: .value(String(localized: "Data"), DayString.date(from: String(row.date.prefix(10))) ?? Date()),
                    y: .value(String(localized: "Waga"), row.weight ?? 0)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.accentColor)
                PointMark(
                    x: .value(String(localized: "Data"), DayString.date(from: String(row.date.prefix(10))) ?? Date()),
                    y: .value(String(localized: "Waga"), row.weight ?? 0)
                )
                .foregroundStyle(Color.accentColor)
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
            .frame(height: 220)
            .padding(.vertical, 8)
        } else {
            ContentUnavailableView {
                Label("Za mało pomiarów do wykresu", systemImage: "chart.line.uptrend.xyaxis")
            } description: {
                Text("Dodaj wagę albo połącz aplikację z Health, żeby zaimportować wcześniejsze pomiary.")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    private func load(sync: Bool = false) async {
        let person = appState.activePersonId
        if rows.isEmpty, let cached: [DiaryRow] = DiskCache.read("diary", person: person) {
            rows = cached
        }
        do {
            rows = try await APIClient.shared.diary(person: person)
            loaded = true
            if sync, HealthWeightSync.isAvailable, health.canShare {
                await syncHealth()
            } else if !sync, health.canShare, loaded {
                await syncHealth()
            }
        } catch {
            guard !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }

    private func connectHealth() async {
        _ = await health.requestAccess()
        await syncHealth()
    }

    private func syncHealth() async {
        let person = appState.activePersonId
        rows = await health.synchronize(person: person, rows: rows)
    }

    private func save(date: Date, weight: Double, id: Int?) async {
        let day = DayString.string(from: date)
        let person = appState.activePersonId
        do {
            let saved = try await APIClient.shared.upsertDiaryWeight(date: day, weight: weight, id: id, person: person)
            rows = try await APIClient.shared.diary(person: person)
            await health.write(saved, person: person)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete(_ row: DiaryRow) async {
        let person = appState.activePersonId
        let day = String(row.date.prefix(10))
        do {
            if row.id > 0 {
                try await APIClient.shared.deleteDiaryEntry(row.id, person: person)
            }
            rows.removeAll { $0.id == row.id && $0.date == row.date }
            await health.delete(day: day, person: person)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private enum WeightRange: String, CaseIterable, Identifiable {
    case days30, days90, year, all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .days30: String(localized: "30 dni")
        case .days90: String(localized: "90 dni")
        case .year: String(localized: "Rok")
        case .all: String(localized: "Wszystko")
        }
    }

    var startDate: Date? {
        let calendar = Calendar.current
        switch self {
        case .days30: return calendar.date(byAdding: .day, value: -30, to: Date())
        case .days90: return calendar.date(byAdding: .day, value: -90, to: Date())
        case .year: return calendar.date(byAdding: .year, value: -1, to: Date())
        case .all: return nil
        }
    }
}

private struct WeightEditor: Identifiable {
    let id = UUID()
    var date: Date
    var weight: Double?
    var entryId: Int?

    init(row: DiaryRow?) {
        if let row, let date = DayString.date(from: String(row.date.prefix(10))) {
            self.date = date
            self.weight = row.weight
            self.entryId = row.id > 0 ? row.id : nil
        } else {
            self.date = Date()
            self.weight = nil
            self.entryId = nil
        }
    }
}

private struct WeightEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var editor: WeightEditor
    var onSave: (Date, Double, Int?) async -> Void
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Data", selection: $editor.date, in: ...Date(), displayedComponents: .date)
                DecimalField("Waga", value: $editor.weight, unit: "kg")
            }
            .navigationTitle(editor.entryId == nil ? String(localized: "Dodaj wagę") : String(localized: "Edytuj wagę"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zapisz") {
                        guard let weight = editor.weight, weight > 0 else { return }
                        saving = true
                        Task {
                            await onSave(editor.date, weight, editor.entryId)
                            saving = false
                            dismiss()
                        }
                    }
                    .disabled(editor.weight == nil || (editor.weight ?? 0) <= 0 || saving)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
