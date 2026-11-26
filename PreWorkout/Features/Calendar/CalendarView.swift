import SwiftUI

enum CalendarMode: String, CaseIterable, Identifiable {
    case month, week
    var id: String { rawValue }
}

/// Tab: month and week calendar with logged workouts, other activities and day notes.
struct CalendarView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("preworkout.calendar.mode") private var mode: CalendarMode = .month
    @State private var anchor = Date()
    @State private var selected = DayString.today
    @State private var workouts: [WorkoutSummary] = []
    @State private var entries: CalendarEntries = [:]
    @State private var notes: [String: String] = [:]
    @State private var categories: [ActivityCategory] = []
    @State private var items: [String: [CalendarItem]] = [:]
    @State private var loading = false
    @State private var editor: CalendarEntryTarget?
    @State private var noteEditor: DayNoteTarget?
    @State private var pendingDelete: CalendarEntry?
    @State private var error: String?

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Widok", selection: $mode) {
                        Text("Miesiąc").tag(CalendarMode.month)
                        Text("Tydzień").tag(CalendarMode.week)
                    }
                    .pickerStyle(.segmented)
                    periodHeader
                    if mode == .month {
                        weekdayRow
                        grid
                    }
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)

                if mode == .month {
                    daySection(selected)
                } else {
                    ForEach(weekDays, id: \.self) { day in
                        daySection(DayString.string(from: day))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Kalendarz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Dziś") { goToday() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Dodaj aktywność", systemImage: "plus") {
                        editor = CalendarEntryTarget(date: selected, item: nil)
                    }
                }
            }
            .onAppear { Task { await load() } }
            .refreshable { await load() }
            .onReceive(NotificationCenter.default.publisher(for: .outboxFlushed)) { _ in Task { await load() } }
            .onChange(of: mode) { _, _ in
                anchor = DayString.date(from: selected) ?? Date()
            }
            .sheet(item: $editor) { target in
                CalendarEntrySheet(
                    target: target,
                    categories: categories.filter { !($0.archived ?? false) }
                ) { draft in
                    await saveEntry(target, draft)
                }
            }
            .sheet(item: $noteEditor) { target in
                DayNoteSheet(target: target) { text in
                    await saveNote(day: target.day, text: text)
                }
            }
            .alert(
                "Usunąć tę aktywność?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                presenting: pendingDelete
            ) { entry in
                Button("Usuń", role: .destructive) { Task { await deleteEntry(entry) } }
                Button("Anuluj", role: .cancel) {}
            } message: { _ in
                Text("Tej operacji nie można cofnąć.")
            }
            .alert("Błąd", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }
    }

    // MARK: Period header + grid

    private var monthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: anchor)) ?? anchor
    }

    private var weekStart: Date {
        calendar.dateInterval(of: .weekOfYear, for: anchor)?.start ?? calendar.startOfDay(for: anchor)
    }

    private var weekDays: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private var periodTitle: String {
        if mode == .month {
            return monthStart.formatted(.dateTime.month(.wide).year())
        }
        guard let last = weekDays.last else { return "" }
        let first = weekStart.formatted(.dateTime.day().month(.abbreviated))
        let end = last.formatted(.dateTime.day().month(.abbreviated))
        return first + " – " + end
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...]) + Array(symbols[..<first])
    }

    private var cells: [Date?] {
        let start = monthStart
        guard let range = calendar.range(of: .day, in: .month, for: start) else { return [] }
        let weekday = calendar.component(.weekday, from: start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: leading)
        for day in range {
            days.append(calendar.date(byAdding: .day, value: day - 1, to: start))
        }
        while days.count % 7 != 0 {
            days.append(nil)
        }
        return days
    }

    private var periodHeader: some View {
        HStack {
            Button {
                shift(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Text(verbatim: periodTitle)
                .font(.headline)
            Spacer()
            Button {
                shift(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
        }
        .buttonStyle(.borderless)
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(verbatim: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                if let date {
                    dayCell(date)
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let key = DayString.string(from: date)
        let isSelected = key == selected
        let isToday = key == DayString.today
        let dayItems = items[key] ?? []
        let hasNote = !(notes[key] ?? "").isEmpty
        return Button {
            selected = key
        } label: {
            VStack(spacing: 3) {
                Text(verbatim: String(calendar.component(.day, from: date)))
                    .font(.callout.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isSelected ? Color.white : (isToday ? Color.accentColor : Color.primary))
                    .frame(width: 30, height: 30)
                    .background {
                        if isSelected {
                            Circle().fill(Color.accentColor)
                        } else if isToday {
                            Circle().strokeBorder(Color.accentColor, lineWidth: 1.5)
                        }
                    }
                HStack(spacing: 3) {
                    ForEach(Array(dayItems.prefix(3).enumerated()), id: \.offset) { _, item in
                        Circle().fill(item.color).frame(width: 5, height: 5)
                    }
                    if hasNote {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.secondary)
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(date, format: .dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Day content

    @ViewBuilder
    private func daySection(_ day: String) -> some View {
        let dayItems = items[day] ?? []
        let note = notes[day] ?? ""
        Section {
            ForEach(dayItems) { item in
                itemRow(item)
            }
            noteRow(day: day, note: note)
            if dayItems.isEmpty && note.isEmpty && mode == .month {
                Text("Brak aktywności tego dnia")
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text(verbatim: DayString.dayLong(day))
                if day == DayString.today {
                    Text("Dziś")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
                Spacer()
                Button {
                    selected = day
                    editor = CalendarEntryTarget(date: day, item: nil)
                } label: {
                    Image(systemName: "plus.circle")
                }
                .accessibilityLabel(Text("Dodaj aktywność"))
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private func itemRow(_ item: CalendarItem) -> some View {
        if let workout = item.workout {
            NavigationLink {
                WorkoutDetailView(workoutId: workout.id)
            } label: {
                itemLabel(item)
            }
        } else if let entry = item.entry {
            Button {
                editor = CalendarEntryTarget(date: item.date, item: item)
            } label: {
                itemLabel(item)
            }
            .foregroundStyle(.primary)
            .swipeActions {
                Button("Usuń", systemImage: "trash", role: .destructive) {
                    pendingDelete = entry
                }
            }
        }
    }

    private func itemLabel(_ item: CalendarItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.symbol)
                .foregroundStyle(item.color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.title)
                    .font(.headline)
                    .lineLimit(1)
                if let text = item.timeText {
                    Text(verbatim: text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let workout = item.workout, !workout.exerciseNames.isEmpty {
                    Text(verbatim: workout.exerciseNames.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let note = item.note, !note.isEmpty {
                    Text(verbatim: note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func noteRow(day: String, note: String) -> some View {
        Button {
            noteEditor = DayNoteTarget(day: day, text: note)
        } label: {
            if note.isEmpty {
                Label("Dodaj notatkę", systemImage: "note.text.badge.plus")
                    .foregroundStyle(.secondary)
            } else {
                Label {
                    Text(verbatim: note)
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "note.text").foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Navigation

    private func shift(_ delta: Int) {
        let component: Calendar.Component = mode == .month ? .month : .weekOfYear
        guard let next = calendar.date(byAdding: component, value: delta, to: anchor) else { return }
        anchor = next
        let today = DayString.today
        if mode == .month {
            let key = String(DayString.string(from: monthStart).prefix(7))
            guard !selected.hasPrefix(key) else { return }
            selected = today.hasPrefix(key) ? today : DayString.string(from: monthStart)
        } else {
            let days = weekDays.map { DayString.string(from: $0) }
            selected = days.contains(today) ? today : (days.first ?? today)
        }
    }

    private func goToday() {
        anchor = Date()
        selected = DayString.today
    }

    // MARK: Data

    private func rebuild() {
        var entryById: [String: (date: String, entry: CalendarEntry)] = [:]
        for (date, byId) in entries {
            for entry in byId.values {
                entryById[entry.id] = (date, entry)
            }
        }
        let merged = Set(workouts.compactMap(\.calendarEntryId).filter { entryById[$0] != nil })
        var result: [String: [CalendarItem]] = [:]

        for (date, byId) in entries {
            for entry in byId.values where !merged.contains(entry.id) {
                let category = entry.type == "activity" ? categories.first { $0.id == entry.activityId } : nil
                let title = entry.type == "activity"
                    ? (category?.name ?? entry.activityId ?? String(localized: "Aktywność"))
                    : (entry.name ?? String(localized: "Aktywność"))
                result[date, default: []].append(
                    CalendarItem(
                        id: "entry-" + entry.id,
                        date: date,
                        title: title,
                        symbol: ActivityStyle.symbol(category?.icon ?? entry.icon),
                        colorId: category?.color ?? entry.color,
                        time: entry.time,
                        timeEnd: entry.timeEnd,
                        note: entry.note,
                        workout: nil,
                        entry: entry
                    )
                )
            }
        }

        for workout in workouts {
            let linked = workout.calendarEntryId.flatMap { entryById[$0] }
            let date = linked?.date ?? workout.date
            let category = categories.first { $0.id == workout.categoryId }
            let title = !workout.title.isEmpty
                ? workout.title
                : (category?.name ?? workout.planDayName ?? String(localized: "Trening"))
            result[date, default: []].append(
                CalendarItem(
                    id: "workout-" + workout.id,
                    date: date,
                    title: title,
                    symbol: "dumbbell",
                    colorId: nil,
                    time: linked?.entry.time,
                    timeEnd: linked?.entry.timeEnd,
                    note: linked?.entry.note,
                    workout: workout,
                    entry: nil
                )
            )
        }

        for key in result.keys {
            result[key]?.sort { ($0.time ?? "99:99", $0.title) < ($1.time ?? "99:99", $1.title) }
        }
        items = result
    }

    private func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        let person = appState.activePersonId
        if workouts.isEmpty, let cached: [WorkoutSummary] = DiskCache.read("workouts", person: person) {
            workouts = cached
        }
        if entries.isEmpty, let cached: CalendarEntries = DiskCache.read("calendar-entries", person: person) {
            entries = cached
        }
        if notes.isEmpty, let cached: [String: String] = DiskCache.read("calendar-notes", person: person) {
            notes = cached
        }
        if categories.isEmpty, let cached: [ActivityCategory] = DiskCache.read("categories", person: person) {
            categories = cached
        }
        rebuild()

        var failure: String?
        do { categories = try await APIClient.shared.categories(person: person) } catch { failure = error.localizedDescription }
        do { entries = try await APIClient.shared.calendarEntries(person: person) } catch { failure = error.localizedDescription }
        do { notes = try await APIClient.shared.calendarNotes(person: person) } catch { failure = error.localizedDescription }
        do { workouts = try await APIClient.shared.workouts(person: person) } catch { failure = error.localizedDescription }
        rebuild()
        if let failure, !Task.isCancelled, items.isEmpty {
            error = failure
        }
    }

    private func saveEntry(_ target: CalendarEntryTarget, _ draft: CalendarEntryDraft) async {
        let person = appState.activePersonId
        do {
            if let entry = target.item?.entry {
                try await APIClient.shared.updateCalendarEntry(
                    entry.id,
                    patch: CalendarEntryPatch(note: draft.note, time: draft.time, timeEnd: draft.timeEnd),
                    person: person
                )
            } else {
                let input: CalendarEntryInput
                if let categoryId = draft.categoryId {
                    input = CalendarEntryInput(
                        type: "activity", activityId: categoryId,
                        time: draft.time, timeEnd: draft.timeEnd,
                        note: draft.note.isEmpty ? nil : draft.note
                    )
                } else {
                    input = CalendarEntryInput(
                        type: "custom", name: draft.name, icon: "other", color: "slate",
                        time: draft.time, timeEnd: draft.timeEnd,
                        note: draft.note.isEmpty ? nil : draft.note
                    )
                }
                _ = try await APIClient.shared.createCalendarEntry(date: draft.date, entry: input, person: person)
                Analytics.send("Calendar.activityAdded")
            }
            entries = try await APIClient.shared.calendarEntries(person: person)
            rebuild()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func deleteEntry(_ entry: CalendarEntry) async {
        let person = appState.activePersonId
        do {
            try await APIClient.shared.deleteCalendarEntry(entry.id, person: person)
            for (date, byId) in entries where byId[entry.id] != nil {
                entries[date]?[entry.id] = nil
            }
            rebuild()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func saveNote(day: String, text: String) async {
        let person = appState.activePersonId
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await APIClient.shared.saveCalendarNote(date: day, note: trimmed, person: person)
            notes[day] = trimmed.isEmpty ? nil : trimmed
            if !trimmed.isEmpty {
                Analytics.send("Calendar.noteAdded")
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: Editors

struct CalendarEntryTarget: Identifiable {
    let id = UUID()
    var date: String
    var item: CalendarItem?
}

struct CalendarEntryDraft {
    var date: String
    /// nil = custom activity named `name`
    var categoryId: String?
    var name: String
    var time: String?
    var timeEnd: String?
    var note: String
}

struct CalendarEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    let target: CalendarEntryTarget
    let categories: [ActivityCategory]
    var onSave: (CalendarEntryDraft) async -> Void

    @State private var date: Date
    @State private var categoryId: String
    @State private var name = ""
    @State private var hasTime: Bool
    @State private var start: Date
    @State private var hasEnd: Bool
    @State private var end: Date
    @State private var note: String
    @State private var saving = false

    init(target: CalendarEntryTarget, categories: [ActivityCategory], onSave: @escaping (CalendarEntryDraft) async -> Void) {
        self.target = target
        self.categories = categories
        self.onSave = onSave
        let entry = target.item?.entry
        _date = State(initialValue: DayString.date(from: target.date) ?? Date())
        _categoryId = State(initialValue: categories.first?.id ?? "")
        _hasTime = State(initialValue: entry?.time != nil)
        let startDate = TimeText.date(from: entry?.time)
        _start = State(initialValue: startDate)
        _hasEnd = State(initialValue: (entry?.timeEnd ?? "").isEmpty == false)
        _end = State(initialValue: TimeText.date(from: entry?.timeEnd, fallback: startDate.addingTimeInterval(3600)))
        _note = State(initialValue: entry?.note ?? "")
    }

    private var canSave: Bool {
        if target.item != nil { return true }
        return !categoryId.isEmpty || !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                if let item = target.item {
                    Section {
                        Label {
                            Text(verbatim: item.title)
                        } icon: {
                            Image(systemName: item.symbol).foregroundStyle(item.color)
                        }
                        LabeledContent("Data") { Text(verbatim: DayString.label(item.date)) }
                    }
                } else {
                    Section {
                        Picker("Aktywność", selection: $categoryId) {
                            ForEach(categories) { category in
                                Label(category.name, systemImage: ActivityStyle.symbol(category.icon))
                                    .tag(category.id)
                            }
                            Label("Inna", systemImage: "ellipsis.circle").tag("")
                        }
                        if categoryId.isEmpty {
                            TextField("Nazwa", text: $name)
                        }
                        DatePicker("Data", selection: $date, displayedComponents: .date)
                    }
                }
                Section {
                    Toggle("Godzina", isOn: $hasTime.animation())
                    if hasTime {
                        DatePicker("Początek", selection: $start, displayedComponents: .hourAndMinute)
                        Toggle("Godzina końca", isOn: $hasEnd.animation())
                        if hasEnd {
                            DatePicker("Koniec", selection: $end, displayedComponents: .hourAndMinute)
                        }
                    }
                }
                Section {
                    TextField("Notatka", text: $note, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .navigationTitle(target.item == nil ? String(localized: "Dodaj aktywność") : String(localized: "Edytuj aktywność"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zapisz") {
                        saving = true
                        let draft = CalendarEntryDraft(
                            date: DayString.string(from: date),
                            categoryId: categoryId.isEmpty ? nil : categoryId,
                            name: name.trimmingCharacters(in: .whitespaces),
                            time: hasTime ? TimeText.string(from: start) : nil,
                            timeEnd: hasTime && hasEnd ? TimeText.string(from: end) : nil,
                            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        Task {
                            await onSave(draft)
                            saving = false
                            dismiss()
                        }
                    }
                    .disabled(!canSave || saving)
                }
            }
        }
        .presentationDetents([.large])
    }
}

struct DayNoteTarget: Identifiable {
    let id = UUID()
    var day: String
    var text: String
}

struct DayNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    let target: DayNoteTarget
    var onSave: (String) async -> Void
    @State private var text: String
    @State private var saving = false

    init(target: DayNoteTarget, onSave: @escaping (String) async -> Void) {
        self.target = target
        self.onSave = onSave
        _text = State(initialValue: target.text)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Notatka dnia", text: $text, axis: .vertical)
                        .lineLimit(4...12)
                } footer: {
                    Text("Pusta notatka usuwa notatkę tego dnia.")
                }
            }
            .navigationTitle(Text(verbatim: DayString.dayLong(target.day)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zapisz") {
                        saving = true
                        let value = text
                        Task {
                            await onSave(value)
                            saving = false
                            dismiss()
                        }
                    }
                    .disabled(saving)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
