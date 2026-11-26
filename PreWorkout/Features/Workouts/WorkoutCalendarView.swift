import SwiftUI

/// Month calendar of logged workouts. Tapping a day shows that day's sessions.
struct WorkoutCalendarView: View {
    @Environment(AppState.self) private var appState
    @State private var month: Date = Date()
    @State private var selected: String = DayString.today
    @State private var workouts: [WorkoutSummary] = []
    @State private var error: String?
    @State private var loaded = false

    private var calendar: Calendar { Calendar.current }

    private var monthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
    }

    private var monthKey: String {
        String(DayString.string(from: monthStart).prefix(7))
    }

    private var monthTitle: String {
        monthStart.formatted(.dateTime.month(.wide).year())
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

    private var marked: Set<String> {
        Set(workouts.map(\.date))
    }

    private var dayWorkouts: [WorkoutSummary] {
        workouts.filter { $0.date == selected }.sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            Section {
                monthHeader
                weekdayRow
                grid
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)

            Section {
                if dayWorkouts.isEmpty {
                    Text("Brak treningów tego dnia")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(dayWorkouts) { workout in
                        NavigationLink {
                            WorkoutDetailView(workoutId: workout.id)
                        } label: {
                            WorkoutRow(workout: workout)
                        }
                    }
                }
            } header: {
                Text(DayString.dayLong(selected))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Kalendarz")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !loaded { await load() }
        }
        .refreshable { await load() }
        .alert("Błąd", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                shiftMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Text(monthTitle)
                .font(.headline)
            Spacer()
            Button {
                shiftMonth(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .contain)
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                if let date {
                    dayCell(date)
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
        .padding(.bottom, 4)
    }

    private func dayCell(_ date: Date) -> some View {
        let key = DayString.string(from: date)
        let isSelected = key == selected
        let isToday = key == DayString.today
        let hasWorkout = marked.contains(key)
        return Button {
            selected = key
        } label: {
            VStack(spacing: 4) {
                Text(verbatim: "\(calendar.component(.day, from: date))")
                    .font(.body.weight(isSelected || isToday ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : .primary)
                    .frame(width: 36, height: 36)
                    .background {
                        if isSelected {
                            Circle().fill(Color.accentColor)
                        } else if isToday {
                            Circle().strokeBorder(Color.accentColor, lineWidth: 1.5)
                        }
                    }
                Circle()
                    .fill(hasWorkout ? (isSelected ? Color.accentColor : Color.primary.opacity(0.55)) : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(date, format: .dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(hasWorkout ? String(localized: "Trening") : "")
    }

    private func shiftMonth(_ delta: Int) {
        guard let next = calendar.date(byAdding: .month, value: delta, to: monthStart) else { return }
        month = next
        let key = String(DayString.string(from: next).prefix(7))
        guard !selected.hasPrefix(key) else { return }
        if DayString.today.hasPrefix(key) {
            selected = DayString.today
        } else if let latest = workouts.filter({ $0.date.hasPrefix(key) }).map(\.date).sorted().last {
            selected = latest
        } else {
            selected = DayString.string(from: next)
        }
    }

    private func load() async {
        let person = appState.activePersonId
        if workouts.isEmpty, let cached: [WorkoutSummary] = DiskCache.read("workouts", person: person) {
            workouts = cached
        }
        do {
            workouts = try await APIClient.shared.workouts(person: person)
            loaded = true
        } catch {
            guard !Task.isCancelled else { return }
            if workouts.isEmpty {
                self.error = error.localizedDescription
            }
        }
    }
}
