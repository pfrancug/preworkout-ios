import Foundation

/// Shows a write that is waiting in the outbox as if the server had accepted it: the cached lists
/// (read offline by `APIClient.get`) are patched. The next successful flush drops these entries
/// and the screens read the server's answer.
enum OptimisticCache {
    private typealias Object = [String: Any]

    private static func cacheKey(_ name: String, person: String?) -> DiskCache.Key? {
        guard let userId = DiskCache.currentUserId() else { return nil }
        return DiskCache.Key(userId: userId, personId: person, name: name)
    }

    private static func read(_ name: String, person: String?) -> Any? {
        guard let key = cacheKey(name, person: person), let cached = DiskCache.readRaw(key) else { return nil }
        return try? JSONSerialization.jsonObject(with: cached.data)
    }

    private static func write(_ value: Any, name: String, person: String?) {
        guard let key = cacheKey(name, person: person),
              JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value) else { return }
        DiskCache.writeRaw(key, etag: nil, data: data)
    }

    // MARK: Diary

    static func diary(_ patch: DiaryWeightPatch, person: String) {
        var rows = (read("diary", person: person) as? [Object]) ?? []
        let index = rows.firstIndex { row in
            if let id = patch.id, id > 0, (row["id"] as? Int) == id { return true }
            return (row["date"] as? String)?.hasPrefix(patch.date) == true
        }
        var row: Object = index.map { rows[$0] } ?? ["id": 0, "date": patch.date]
        if patch.includeWeight { row["weight"] = patch.weight ?? NSNull() }
        if let source = patch.source { row["source"] = source.rawValue }
        if patch.includeHealthWeight { row["healthWeight"] = patch.healthWeight ?? NSNull() }
        if let index { rows[index] = row } else { rows.append(row) }
        write(rows, name: "diary", person: person)
    }

    // MARK: Profile

    static func settings(_ body: Data, person: String) {
        guard let key = cacheKey("settings", person: person) else { return }
        DiskCache.writeRaw(key, etag: nil, data: body)
    }

    // MARK: Workouts

    static func workout(_ input: WorkoutInput, body: Data, person: String) {
        if let key = cacheKey("workout-\(input.id)", person: person) {
            DiskCache.writeRaw(key, etag: nil, data: body)
        }
        var list = (read("workouts", person: person) as? [Object]) ?? []
        let index = list.firstIndex { ($0["id"] as? String) == input.id }
        var summary: Object = index.map { list[$0] } ?? [
            "planDayName": NSNull(), "planName": NSNull(), "exerciseNames": [String]()
        ]
        summary["id"] = input.id
        summary["date"] = input.date
        summary["title"] = input.title
        summary["categoryId"] = input.categoryId ?? NSNull()
        summary["calendarEntryId"] = input.calendarEntryId ?? NSNull()
        summary["planDayId"] = input.planDayId ?? NSNull()
        summary["durationMin"] = input.durationMin ?? NSNull()
        summary["rpe"] = input.rpe ?? NSNull()
        summary["exerciseCount"] = input.exercises.count
        summary["setCount"] = input.exercises.reduce(0) { $0 + $1.sets.count }
        if let index { list[index] = summary } else { list.append(summary) }
        write(list, name: "workouts", person: person)
    }

    static func removeWorkout(_ id: String, person: String) {
        if var list = read("workouts", person: person) as? [Object] {
            list.removeAll { ($0["id"] as? String) == id }
            write(list, name: "workouts", person: person)
        }
        if let key = cacheKey("workout-\(id)", person: person) { DiskCache.remove(key) }
    }

    // MARK: Calendar

    static func calendarNote(date: String, note: String, person: String) {
        var notes = (read("calendar-notes", person: person) as? [String: String]) ?? [:]
        if note.isEmpty { notes[date] = nil } else { notes[date] = note }
        write(notes, name: "calendar-notes", person: person)
    }

    static func calendarEntry(_ id: String, patch: CalendarEntryPatch, person: String) {
        guard var days = read("calendar-entries", person: person) as? [String: [String: Object]] else { return }
        for (date, entries) in days where entries[id] != nil {
            var entry = entries[id] ?? [:]
            if patch.note.isEmpty { entry["note"] = nil } else { entry["note"] = patch.note }
            entry["time"] = patch.time
            entry["timeEnd"] = patch.timeEnd
            days[date]?[id] = entry
        }
        write(days, name: "calendar-entries", person: person)
    }

    static func removeCalendarEntry(_ id: String, person: String) {
        guard var days = read("calendar-entries", person: person) as? [String: [String: Object]] else { return }
        for date in days.keys {
            days[date]?[id] = nil
            if days[date]?.isEmpty == true { days[date] = nil }
        }
        write(days, name: "calendar-entries", person: person)
    }
}
