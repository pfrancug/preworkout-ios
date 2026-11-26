import Charts
import SwiftUI

/// Weight history: chart, add/edit, and two-way Apple Health sync.
struct WeightView: View {
    @Environment(AppState.self) private var appState
    @State private var rows: [DiaryRow] = []
    @State private var range: WeightRange = .months6
    @State private var editor: WeightEditor?
    @State private var pendingDelete: DiaryRow?
    @State private var error: String?
    @State private var health = HealthWeightSync()
    @State private var loaded = false

    private var weighIns: [DiaryRow] {
        rows.filter(\.hasAnyWeight)
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
                            Label("Synchronizuj z Health", systemImage: "heart")
                        }
                        .disabled(health.busy)
                        syncProgress
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
                            WeightEntryRow(row: row)
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
        .confirmationDialog(
            "Usunąć ten pomiar?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { row in
            if row.hasBothWeights {
                Button("Usuń z aplikacji", role: .destructive) {
                    Task { await delete(row, clearing: .app) }
                }
                Button("Usuń z Health", role: .destructive) {
                    Task { await delete(row, clearing: .health) }
                }
                Button("Usuń oba", role: .destructive) {
                    Task { await delete(row, clearing: .both) }
                }
            } else {
                Button("Usuń", role: .destructive) {
                    Task { await delete(row, clearing: .both) }
                }
            }
            Button("Anuluj", role: .cancel) {}
        } message: { row in
            if row.hasBothWeights {
                Text("Ten dzień ma wagę z aplikacji i z Health.")
            } else {
                Text("Tej operacji nie można cofnąć.")
            }
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
        .onReceive(NotificationCenter.default.publisher(for: .outboxFlushed)) { _ in Task { await load() } }
        .onChange(of: health.lastError) { _, newValue in
            if let newValue { error = newValue }
        }
    }

    @ViewBuilder
    private var syncProgress: some View {
        if let progress = health.progress {
            VStack(alignment: .leading, spacing: 8) {
                if progress.phase == .done {
                    Label("Zsynchronizowano", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if progress.total > 0 {
                    ProgressView(value: progress.fraction)
                    Text(progressLabel(progress))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(progressLabel(progress))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func progressLabel(_ progress: HealthSyncProgress) -> String {
        let done = progress.done
        let total = progress.total
        switch progress.phase {
        case .reading:
            return String(localized: "Wczytywanie z Health…")
        case .importing:
            return String(localized: "Importowanie \(done)/\(total)")
        case .writing:
            return String(localized: "Zapisywanie do Health \(done)/\(total)")
        case .done:
            return String(localized: "Zsynchronizowano")
        }
    }

    @ViewBuilder
    private var chart: some View {
        let data = buckets
        if visible.count >= 2 {
            let showPoints = data.count <= 45
            Chart {
                if range.granularity != .day {
                    ForEach(data) { bucket in
                        AreaMark(
                            x: .value(String(localized: "Data"), bucket.date),
                            yStart: .value(String(localized: "Waga"), bucket.low),
                            yEnd: .value(String(localized: "Waga"), bucket.high)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Color.accentColor.opacity(0.15))
                    }
                }
                ForEach(data) { bucket in
                    LineMark(
                        x: .value(String(localized: "Data"), bucket.date),
                        y: .value(String(localized: "Waga"), bucket.trend)
                    )
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .foregroundStyle(Color.accentColor)
                }
                if showPoints {
                    ForEach(plotPoints(data)) { point in
                        PointMark(
                            x: .value(String(localized: "Data"), point.date),
                            y: .value(String(localized: "Waga"), point.kg)
                        )
                        .symbolSize(point.source == .app ? 22 : 16)
                        .foregroundStyle(by: .value(String(localized: "Źródło"), point.sourceTitle))
                        .symbol(by: .value(String(localized: "Źródło"), point.sourceTitle))
                    }
                }
            }
            .chartForegroundStyleScale([
                String(localized: "Aplikacja"): Color.accentColor,
                String(localized: "Health"): Color.pink,
            ])
            .chartYScale(domain: yDomain(for: data))
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) }
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

    /// Daily values for short ranges, weekly averages for ~6 months, monthly averages beyond.
    private var buckets: [WeightBucket] {
        let calendar = Calendar.current
        var groups: [Date: [DiaryRow]] = [:]
        for row in visible {
            guard let day = DayString.date(from: String(row.date.prefix(10))) else { continue }
            groups[range.granularity.bucketStart(for: day, calendar: calendar), default: []].append(row)
        }
        return groups.compactMap { start, rows -> WeightBucket? in
            let trends = rows.compactMap(\.displayWeight)
            guard !trends.isEmpty else { return nil }
            let all = rows.flatMap { [$0.appWeight, $0.importedWeight].compactMap { $0 } }
            let apps = rows.compactMap(\.appWeight)
            let healths = rows.compactMap(\.importedWeight)
            return WeightBucket(
                date: start,
                app: apps.isEmpty ? nil : apps.reduce(0, +) / Double(apps.count),
                health: healths.isEmpty ? nil : healths.reduce(0, +) / Double(healths.count),
                trend: trends.reduce(0, +) / Double(trends.count),
                low: all.min() ?? trends.min() ?? 0,
                high: all.max() ?? trends.max() ?? 0
            )
        }
        .sorted { $0.date < $1.date }
    }

    private func plotPoints(_ data: [WeightBucket]) -> [WeightChartPoint] {
        data.flatMap { bucket -> [WeightChartPoint] in
            var points: [WeightChartPoint] = []
            if let kg = bucket.app {
                points.append(WeightChartPoint(id: "\(bucket.date.timeIntervalSince1970)-app", date: bucket.date, kg: kg, source: .app))
            }
            if let kg = bucket.health {
                points.append(WeightChartPoint(id: "\(bucket.date.timeIntervalSince1970)-health", date: bucket.date, kg: kg, source: .health))
            }
            return points
        }
    }

    /// Fit the axis to the data (like Apple Health) instead of starting at zero.
    private func yDomain(for data: [WeightBucket]) -> ClosedRange<Double> {
        guard let low = data.map(\.low).min(), let high = data.map(\.high).max() else { return 0...1 }
        let pad = max((high - low) * 0.1, 0.5)
        return floor(low - pad)...ceil(high + pad)
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
        guard health.progress?.phase == .done else { return }
        try? await Task.sleep(for: .seconds(2.5))
        if health.progress?.phase == .done {
            health.progress = nil
        }
    }

    private func save(date: Date, weight: Double, id: Int?) async {
        let day = DayString.string(from: date)
        let person = appState.activePersonId
        do {
            let saved = try await APIClient.shared.upsertDiaryWeight(date: day, weight: weight, id: id, person: person)
            if id == nil {
                Analytics.send("Weight.entryAdded")
            }
            rows = try await APIClient.shared.diary(person: person)
            await health.write(saved, person: person)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete(_ row: DiaryRow, clearing: WeightClearing) async {
        let person = appState.activePersonId
        let day = String(row.date.prefix(10))
        do {
            if row.id > 0 {
                try await clearWeights(row, day: day, person: person, clearing: clearing)
                rows = try await APIClient.shared.diary(person: person)
            } else {
                rows.removeAll { $0.id == row.id && $0.date == row.date }
            }
            if clearing != .health {
                await health.delete(day: day, person: person)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func clearWeights(
        _ row: DiaryRow,
        day: String,
        person: String,
        clearing: WeightClearing
    ) async throws {
        let patch: DiaryWeightPatch
        switch clearing {
        case .app:
            patch = DiaryWeightPatch(
                id: row.id,
                date: day,
                weight: nil,
                source: .app,
                includeWeight: true,
                includeHealthWeight: false
            )
        case .health:
            patch = DiaryWeightPatch(
                id: row.id,
                date: day,
                healthWeight: nil,
                includeWeight: false,
                includeHealthWeight: true
            )
        case .both:
            patch = DiaryWeightPatch(
                id: row.id,
                date: day,
                weight: nil,
                source: .app,
                healthWeight: nil,
                includeWeight: true,
                includeHealthWeight: true
            )
        }
        _ = try await APIClient.shared.upsertDiaryPatch(patch, person: person)
    }
}

private enum WeightClearing {
    case app, health, both
}

private struct WeightChartPoint: Identifiable {
    var id: String
    var date: Date
    var kg: Double
    var source: DiaryWeightSource

    var sourceTitle: String {
        switch source {
        case .app: String(localized: "Aplikacja")
        case .health: String(localized: "Health")
        }
    }
}

private struct WeightEntryRow: View {
    let row: DiaryRow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(DayString.label(String(row.date.prefix(10))))
            HStack(spacing: 12) {
                if let kg = row.appWeight {
                    weightValue(kg, source: .app)
                }
                if let kg = row.importedWeight {
                    weightValue(kg, source: .health)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func weightValue(_ kg: Double, source: DiaryWeightSource) -> some View {
        HStack(spacing: 6) {
            WeightSourceBadge(source: source)
            Text(verbatim: "\(kg.short()) kg")
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(source == .app
            ? String(localized: "Dodane w PreWorkout")
            : String(localized: "Zaimportowano z Apple Health"))
        .accessibilityValue(Text(verbatim: "\(kg.short()) kg"))
    }
}

private struct WeightSourceBadge: View {
    let source: DiaryWeightSource

    var body: some View {
        Text(source == .app ? String(localized: "Aplikacja") : String(localized: "Health"))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background((source == .app ? Color.accentColor : Color.pink).opacity(0.15))
            .foregroundStyle(source == .app ? Color.accentColor : Color.pink)
            .clipShape(Capsule())
            .accessibilityHidden(true)
    }
}

private enum WeightGranularity {
    case day, week, month

    func bucketStart(for day: Date, calendar: Calendar) -> Date {
        switch self {
        case .day:
            return calendar.startOfDay(for: day)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? calendar.startOfDay(for: day)
        case .month:
            return calendar.dateInterval(of: .month, for: day)?.start ?? calendar.startOfDay(for: day)
        }
    }
}

private struct WeightBucket: Identifiable {
    var id: Date { date }
    var date: Date
    var app: Double?
    var health: Double?
    /// Average of the preferred value (app, otherwise Health).
    var trend: Double
    var low: Double
    var high: Double
}

private enum WeightRange: String, CaseIterable, Identifiable {
    case week, month, months6, year, all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: String(localized: "Tydz.")
        case .month: String(localized: "Mies.")
        case .months6: String(localized: "6 mies.")
        case .year: String(localized: "Rok")
        case .all: String(localized: "Wszystko")
        }
    }

    var granularity: WeightGranularity {
        switch self {
        case .week, .month: .day
        case .months6: .week
        case .year, .all: .month
        }
    }

    var startDate: Date? {
        let calendar = Calendar.current
        switch self {
        case .week: return calendar.date(byAdding: .day, value: -7, to: Date())
        case .month: return calendar.date(byAdding: .month, value: -1, to: Date())
        case .months6: return calendar.date(byAdding: .month, value: -6, to: Date())
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
    var importedWeight: Double?

    init(row: DiaryRow?) {
        if let row, let date = DayString.date(from: String(row.date.prefix(10))) {
            self.date = date
            self.weight = row.appWeight ?? row.importedWeight
            self.entryId = row.id > 0 ? row.id : nil
            self.importedWeight = row.hasBothWeights ? row.importedWeight : nil
        } else {
            self.date = Date()
            self.weight = nil
            self.entryId = nil
            self.importedWeight = nil
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
                if let imported = editor.importedWeight {
                    LabeledContent("Health") {
                        Text(verbatim: "\(imported.short()) kg")
                            .monospacedDigit()
                    }
                    Text("Zaimportowano z Apple Health")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
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
