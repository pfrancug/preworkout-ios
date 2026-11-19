import SwiftUI

/// Calendar: pick a day, see its activities, logged workouts and the day note.
/// (The web app uses FullCalendar month/week views; a native month grid with
/// colored dots comes in a later milestone.)
struct CalendarView: View {
    @Environment(AppState.self) private var appState
    @State private var selected = Date()
    @State private var state: LoadState<CalendarData> = .idle

    struct CalendarData {
        var entries: CalendarEntries
        var notes: [String: String]
        var categories: [String: ActivityCategory]
        var workouts: [WorkoutSummary]
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker("Dzień", selection: $selected, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                }
                LoadStateView(state: state, retry: load) { data in
                    DaySection(day: DayString.string(from: selected), data: data)
                }
            }
            .navigationTitle("Kalendarz")
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private func load() async {
        if case .loaded = state {} else { state = .loading }
        let id = appState.activePersonId
        let api = APIClient.shared
        do {
            async let entries = api.calendarEntries(person: id)
            async let notes = api.calendarNotes(person: id)
            async let categories = api.categories(person: id)
            async let workouts = api.workouts(person: id)
            let byId = Dictionary(try await categories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            state = .loaded(CalendarData(entries: try await entries, notes: try await notes,
                                         categories: byId, workouts: try await workouts))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

private struct DaySection: View {
    let day: String
    let data: CalendarView.CalendarData

    private var entries: [CalendarEntry] {
        (data.entries[day].map { Array($0.values) } ?? []).sorted { ($0.time ?? "") < ($1.time ?? "") }
    }

    private var workouts: [WorkoutSummary] { data.workouts.filter { $0.date == day } }

    var body: some View {
        Section(DayString.label(day)) {
            if entries.isEmpty && workouts.isEmpty && data.notes[day] == nil {
                Text("Nic tego dnia").foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                HStack {
                    Text(title(entry))
                    Spacer()
                    if let time = entry.time {
                        Text(entry.timeEnd.map { "\(time)–\($0)" } ?? time)
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(workouts) { workout in
                Label(workout.title.isEmpty ? (workout.planDayName ?? String(localized: "Trening")) : workout.title,
                      systemImage: "dumbbell")
            }
            if let note = data.notes[day], !note.isEmpty {
                Text(note).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func title(_ entry: CalendarEntry) -> String {
        if entry.type == "activity", let id = entry.activityId, let category = data.categories[id] {
            return category.name
        }
        return entry.name ?? "–"
    }
}
